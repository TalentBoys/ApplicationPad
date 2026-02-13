//
//  AppGridView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI

struct AppGridView: View {
    @State private var searchText = ""
    @State private var apps = AppScanner.scan()
    @State private var gridItems: [LauncherItem] = []  // Display order, updated during drag
    @State private var keyMonitor = KeyEventMonitor()
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var scrollMonitor: Any?
    @State private var pageWidth: CGFloat = 0
    @State private var scrollEndTimer: Timer?
    @FocusState private var isSearchFocused: Bool

    // Drag-to-reorder state
    @State private var draggingItem: LauncherItem?
    @State private var draggingOffset: CGSize = .zero
    @State private var dragCurrentIndex: Int?
    @State private var dragStartPosition: CGPoint = .zero
    @State private var dragAccumulatedOffset: CGSize = .zero  // Compensate for dragStartPosition changes
    @State private var dragMouseOffset: CGSize = .zero  // Mouse click position relative to icon center
    @State private var isDraggingPage: Bool = false

    // State machine for drag behavior
    @StateObject private var dragStateMachine = DragStateMachine()

    // Folder merge state (derived from state machine)
    private var mergeTargetId: UUID? {
        dragStateMachine.mergeState.targetId
    }
    private var isMergeHovering: Bool {
        dragStateMachine.mergeState.isHovering
    }
    private var isMergeReady: Bool {
        dragStateMachine.mergeState.isReady
    }

    // Open folder state
    @State private var openFolder: FolderItem?
    @State private var openFolderPosition: CGPoint = .zero

    var columnsCount: Int { LauncherSettings.columnsCount }
    var rowsCount: Int { LauncherSettings.rowsCount }
    var appsPerPage: Int { LauncherSettings.appsPerPage }
    var iconSize: CGFloat { LauncherSettings.iconSize }
    var horizontalPadding: CGFloat { LauncherSettings.horizontalPadding }
    var topPadding: CGFloat { LauncherSettings.topPadding }
    var bottomPadding: CGFloat { LauncherSettings.bottomPadding }

    var filteredItems: [LauncherItem] {
        let key = searchText.lowercased()
        if key.isEmpty {
            return gridItems.isEmpty ? LauncherSettings.applyCustomOrder(to: apps) : gridItems
        }
        // When searching, flatten folders and search all apps
        var allApps: [AppItem] = []
        for item in gridItems {
            switch item {
            case .app(let app):
                allApps.append(app)
            case .folder(let folder):
                allApps.append(contentsOf: folder.apps)
            }
        }
        return allApps.filter {
            $0.name.localizedCaseInsensitiveContains(key)
            || $0.pinyinName.contains(key)
            || $0.pinyinInitials.contains(key)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        .map { .app($0) }
    }

    private func refreshGridItems() {
        gridItems = LauncherSettings.applyCustomOrder(to: apps)
    }

    var totalPages: Int {
        max(1, Int(ceil(Double(filteredItems.count) / Double(appsPerPage))))
    }

    func itemsForPage(_ page: Int) -> [LauncherItem] {
        let start = page * appsPerPage
        let end = min(start + appsPerPage, filteredItems.count)
        guard start < filteredItems.count else { return [] }
        return Array(filteredItems[start..<end])
    }

    var body: some View {
        GeometryReader { geometry in
            let screenHeight = geometry.size.height
            let notchHeight: CGFloat = 50
            let searchHeight: CGFloat = 60
            let pageIndicatorHeight: CGFloat = totalPages > 1 ? 50 : 0
            let availableHeight = screenHeight - notchHeight - searchHeight - pageIndicatorHeight - topPadding - bottomPadding

            ZStack {
                VStack(spacing: 0) {
                    Spacer()
                        .frame(height: notchHeight)
                    // Search box
                    TextField("Search applications", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 300)
                        .frame(height: searchHeight)
                        .focused($isSearchFocused)
                        .onChange(of: searchText) { _, _ in
                            currentPage = 0
                        }
                        .onTapGesture { }

                    // Paged grid
                    GeometryReader { geo in
                        let cellWidth = (geo.size.width - horizontalPadding * 2) / CGFloat(columnsCount)
                        let cellHeight = (geo.size.height - topPadding - bottomPadding) / CGFloat(rowsCount)

                        ZStack {
                            HStack(spacing: 0) {
                                ForEach(0..<totalPages, id: \.self) { page in
                                    let pageItems = itemsForPage(page)
                                    ZStack {
                                        ForEach(Array(pageItems.enumerated()), id: \.element.id) { index, item in
                                            let globalIndex = page * appsPerPage + index
                                            let row = index / columnsCount
                                            let col = index % columnsCount
                                            let x = horizontalPadding + cellWidth * (CGFloat(col) + 0.5)
                                            let y = topPadding + cellHeight * (CGFloat(row) + 0.5)
                                            let isDragging = draggingItem?.id == item.id
                                            let isMergeTarget = mergeTargetId == item.id
                                            let isMergeHoveringTarget = isMergeHovering && isMergeTarget
                                            let isMergeReadyTarget = isMergeReady && isMergeTarget

                                            let displayX = isDragging ? dragStartPosition.x + draggingOffset.width : x
                                            let displayY = isDragging ? dragStartPosition.y + draggingOffset.height : y

                                            GridItemView(
                                                item: item,
                                                iconSize: iconSize,
                                                isMergeTarget: isMergeTarget,
                                                isMergeHovering: isMergeHoveringTarget,
                                                isMergeReady: isMergeReadyTarget,
                                                onTap: {
                                                    handleItemTap(item: item, position: CGPoint(x: x, y: y))
                                                },
                                                onAppLaunch: {
                                                    apps = AppScanner.scan()
                                                    refreshGridItems()
                                                }
                                            )
                                            .scaleEffect(isDragging ? 1.1 : (isMergeReadyTarget ? 1.15 : (isMergeHoveringTarget ? 0.9 : 1.0)))
                                            .zIndex(isDragging ? 100 : 0)
                                            .opacity(isDragging ? 0.9 : 1.0)
                                            // Only animate position for non-dragging items to avoid flicker
                                            .animation(isDragging ? nil : .easeInOut(duration: 0.2), value: globalIndex)
                                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isMergeHoveringTarget)
                                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isMergeReadyTarget)
                                            .position(x: displayX, y: displayY)  // position 放最后，避免坐标系偏移
                                            .highPriorityGesture(
                                                DragGesture(minimumDistance: 15)
                                                    .onChanged { drag in
                                                        if draggingItem == nil && searchText.isEmpty {
                                                            draggingItem = item
                                                            dragCurrentIndex = globalIndex
                                                            dragStartPosition = CGPoint(x: x, y: y)
                                                            dragAccumulatedOffset = .zero
                                                            // Record mouse click position relative to icon center
                                                            // This ensures the icon stays "attached" to where the user clicked
                                                            dragMouseOffset = CGSize(
                                                                width: drag.startLocation.x - x,
                                                                height: drag.startLocation.y - y
                                                            )
                                                            dragStateMachine.startDrag()
                                                            setupStateMachineCallbacks(cellWidth: cellWidth, cellHeight: cellHeight)
                                                        }

                                                        if draggingItem?.id == item.id {
                                                            // Apply accumulated offset and mouse offset to keep icon attached to cursor
                                                            draggingOffset = CGSize(
                                                                width: drag.translation.width + dragAccumulatedOffset.width + dragMouseOffset.width,
                                                                height: drag.translation.height + dragAccumulatedOffset.height + dragMouseOffset.height
                                                            )

                                                            let dragX = dragStartPosition.x + draggingOffset.width
                                                            let dragY = dragStartPosition.y + draggingOffset.height

                                                            updateDragPosition(
                                                                dragX: dragX,
                                                                dragY: dragY,
                                                                cellWidth: cellWidth,
                                                                cellHeight: cellHeight
                                                            )
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        if draggingItem?.id == item.id {
                                                            finishDragging()
                                                        }
                                                    }
                                            )
                                        }
                                    }
                                    .frame(width: geo.size.width, height: geo.size.height)
                                }
                            }
                            .offset(x: -CGFloat(currentPage) * geo.size.width + dragOffset)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if !isDraggingPage && draggingItem == nil {
                                if openFolder != nil {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        openFolder = nil
                                    }
                                } else {
                                    closeLauncher()
                                }
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 15)
                                .onChanged { value in
                                    if draggingItem == nil {
                                        isDraggingPage = true
                                        dragOffset = value.translation.width

                                        if currentPage == 0 && dragOffset > 0 {
                                            dragOffset = min(dragOffset, 100)
                                        } else if currentPage == totalPages - 1 && dragOffset < 0 {
                                            dragOffset = max(dragOffset, -100)
                                        }
                                    }
                                }
                                .onEnded { value in
                                    if draggingItem == nil {
                                        let threshold = geo.size.width * 0.2

                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            if value.translation.width < -threshold && currentPage < totalPages - 1 {
                                                currentPage += 1
                                            } else if value.translation.width > threshold && currentPage > 0 {
                                                currentPage -= 1
                                            }
                                            dragOffset = 0
                                        }
                                    }
                                    isDraggingPage = false
                                }
                        )
                        .onAppear {
                            pageWidth = geo.size.width
                        }
                        .onChange(of: geo.size.width) { _, newWidth in
                            pageWidth = newWidth
                        }
                    }
                    .frame(height: availableHeight + topPadding + bottomPadding)
                    .onAppear {
                        startScrollMonitor()
                    }
                    .onDisappear {
                        stopScrollMonitor()
                    }

                    // Page indicator
                    if totalPages > 1 {
                        HStack(spacing: 8) {
                            ForEach(0..<totalPages, id: \.self) { page in
                                Circle()
                                    .fill(page == currentPage ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 8, height: 8)
                                    .onTapGesture {
                                        withAnimation {
                                            currentPage = page
                                        }
                                    }
                            }
                        }
                        .frame(height: pageIndicatorHeight)
                    }
                }

                // Folder overlay
                if let folder = openFolder {
                    FolderOverlayView(
                        folder: folder,
                        iconSize: iconSize,
                        position: openFolderPosition,
                        onClose: {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                openFolder = nil
                            }
                        },
                        onAppLaunch: {
                            apps = AppScanner.scan()
                            refreshGridItems()
                        },
                        onFolderUpdate: { updatedFolder in
                            updateFolder(updatedFolder)
                        }
                    )
                }
            }
        }
        .onAppear {
            refreshGridItems()
            focusSearchField()
            keyMonitor.startEscListener {
                if openFolder != nil {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        openFolder = nil
                    }
                } else {
                    closeLauncher()
                }
            }
        }
        .onDisappear {
            keyMonitor.stop()
            searchText = ""
            currentPage = 0
            openFolder = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            focusSearchField()
        }
    }

    private func handleItemTap(item: LauncherItem, position: CGPoint) {
        if case .folder(let folder) = item {
            openFolderPosition = position
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                openFolder = folder
            }
        }
    }

    private func updateFolder(_ updatedFolder: FolderItem) {
        if let index = gridItems.firstIndex(where: {
            if case .folder(let f) = $0 { return f.id == updatedFolder.id }
            return false
        }) {
            if updatedFolder.apps.isEmpty {
                gridItems.remove(at: index)
            } else if updatedFolder.apps.count == 1 {
                // Folder has only one app, convert back to single app
                gridItems[index] = .app(updatedFolder.apps[0])
            } else {
                gridItems[index] = .folder(updatedFolder)
            }
            LauncherSettings.saveGridItems(gridItems)
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFocused = true
        }
    }

    private func closeLauncher() {
        LauncherPanel.shared.close()
        searchText = ""
        currentPage = 0
        openFolder = nil
    }

    private func updateDragPosition(dragX: CGFloat, dragY: CGFloat, cellWidth: CGFloat, cellHeight: CGFloat) {
        guard let _ = dragCurrentIndex, let dragging = draggingItem else { return }

        // Use state machine for hit detection and state management
        dragStateMachine.updateDrag(
            position: CGPoint(x: dragX, y: dragY),
            gridItems: gridItems,
            draggingItemId: dragging.id,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            iconSize: iconSize,
            columnsCount: columnsCount,
            rowsCount: rowsCount,
            horizontalPadding: horizontalPadding,
            topPadding: topPadding,
            currentPage: currentPage,
            appsPerPage: appsPerPage
        )
    }

    private func setupStateMachineCallbacks(cellWidth: CGFloat, cellHeight: CGFloat) {
        dragStateMachine.onReorder = { [self] targetIndex in
            guard let currentIndex = dragCurrentIndex,
                  let dragging = draggingItem,
                  targetIndex != currentIndex,
                  targetIndex >= 0,
                  targetIndex < gridItems.count else { return }

            // Perform reorder
            // After remove(at: currentIndex), indices shift:
            // - Elements before currentIndex: unchanged
            // - Elements at/after currentIndex: shift left by 1
            //
            // When dragging right (targetIndex > currentIndex):
            //   The target element shifts from targetIndex to targetIndex-1
            //   To place our item AFTER the target, insert at targetIndex (which is where the next element is now)
            //   Example: [A,B,C] drag A(0) to B(1)'s position
            //     remove(0) → [B,C], insert(at:1) → [B,A,C] ✓
            //
            // When dragging left (targetIndex < currentIndex):
            //   The target element stays at targetIndex (it's before the removed position)
            //   Insert at targetIndex to place AT the target position
            //   Example: [A,B,C] drag C(2) to A(0)'s position
            //     remove(2) → [A,B], insert(at:0) → [C,A,B] ✓
            withAnimation(.easeInOut(duration: 0.2)) {
                gridItems.remove(at: currentIndex)
                let newIndex = min(targetIndex, gridItems.count)
                gridItems.insert(dragging, at: newIndex)
                dragCurrentIndex = newIndex
            }

            // Calculate new cell position
            let newIndexInPage = dragCurrentIndex! % appsPerPage
            let newRow = newIndexInPage / columnsCount
            let newCol = newIndexInPage % columnsCount
            let newStartPosition = CGPoint(
                x: horizontalPadding + cellWidth * (CGFloat(newCol) + 0.5),
                y: topPadding + cellHeight * (CGFloat(newRow) + 0.5)
            )

            // Accumulate the offset to compensate for dragStartPosition change
            // When dragStartPosition moves by delta, we need to add -delta to accumulated offset
            // so that: newStartPosition + (translation + newAccumulated) = oldStartPosition + (translation + oldAccumulated)
            let deltaX = newStartPosition.x - dragStartPosition.x
            let deltaY = newStartPosition.y - dragStartPosition.y
            dragAccumulatedOffset = CGSize(
                width: dragAccumulatedOffset.width - deltaX,
                height: dragAccumulatedOffset.height - deltaY
            )

            // CRITICAL: Update draggingOffset immediately to prevent flicker
            // displayX/Y = dragStartPosition + draggingOffset
            // After updating dragStartPosition, we must also update draggingOffset in the same frame
            // to maintain the same visual position
            draggingOffset = CGSize(
                width: draggingOffset.width - deltaX,
                height: draggingOffset.height - deltaY
            )

            dragStartPosition = newStartPosition
        }

        dragStateMachine.onMergeReady = { targetId in
            // Visual feedback is handled by state machine state
            // Haptic feedback for trackpad
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    private func performMerge(draggingItem: LauncherItem, targetItem: LauncherItem, targetIndex: Int, currentIndex: Int) {
        // Get apps from both items
        var appsToMerge: [AppItem] = []

        switch targetItem {
        case .app(let app):
            appsToMerge.append(app)
        case .folder(let folder):
            appsToMerge.append(contentsOf: folder.apps)
        }

        switch draggingItem {
        case .app(let app):
            appsToMerge.append(app)
        case .folder(let folder):
            appsToMerge.append(contentsOf: folder.apps)
        }

        // Create new folder
        let folderName = "Folder"  // Default name
        let newFolder = FolderItem(name: folderName, apps: appsToMerge)

        // Update grid items
        withAnimation(.easeInOut(duration: 0.2)) {
            // Remove both items (remove higher index first to avoid index shifting issues)
            let indicesToRemove = [currentIndex, targetIndex].sorted(by: >)
            for idx in indicesToRemove {
                gridItems.remove(at: idx)
            }

            // Insert folder at the lower index
            let insertIndex = min(currentIndex, targetIndex)
            gridItems.insert(.folder(newFolder), at: min(insertIndex, gridItems.count))
        }

        // Clear dragging state
        self.draggingItem = nil
        draggingOffset = .zero
        dragCurrentIndex = nil
        dragStartPosition = .zero
        dragAccumulatedOffset = .zero
        dragMouseOffset = .zero
        dragStateMachine.reset()

        // Save
        LauncherSettings.saveGridItems(gridItems)
    }

    private func finishDragging() {
        // Ask state machine if we should merge
        let (shouldMerge, targetId) = dragStateMachine.endDrag()

        if shouldMerge,
           let targetId = targetId,
           let currentIndex = dragCurrentIndex,
           let dragging = draggingItem,
           let targetIndex = gridItems.firstIndex(where: { $0.id == targetId }) {
            let targetItem = gridItems[targetIndex]
            performMerge(draggingItem: dragging, targetItem: targetItem, targetIndex: targetIndex, currentIndex: currentIndex)
            return
        }

        // Save the final order
        if !gridItems.isEmpty {
            LauncherSettings.saveGridItems(gridItems)
        }

        withAnimation(.easeOut(duration: 0.2)) {
            draggingItem = nil
            draggingOffset = .zero
            dragCurrentIndex = nil
            dragStartPosition = .zero
            dragAccumulatedOffset = .zero
            dragMouseOffset = .zero
        }
    }

    private func startScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            if event.momentumPhase != [] {
                return event
            }

            let invert: CGFloat = LauncherSettings.invertScroll ? -1 : 1
            let sensitivity = LauncherSettings.scrollSensitivity

            let deltaX = event.scrollingDeltaX * invert * sensitivity
            let deltaY = event.scrollingDeltaY * invert * sensitivity

            let delta = deltaX - deltaY

            guard abs(delta) > 0.1 else { return event }

            dragOffset += delta

            let maxOffset = pageWidth > 0 ? pageWidth : 1000
            dragOffset = max(-maxOffset, min(maxOffset, dragOffset))

            if currentPage == 0 && dragOffset > 0 {
                dragOffset = min(dragOffset, 100)
            } else if currentPage == totalPages - 1 && dragOffset < 0 {
                dragOffset = max(dragOffset, -100)
            }

            scrollEndTimer?.invalidate()
            scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                DispatchQueue.main.async {
                    let threshold = pageWidth * 0.15
                    let currentDragOffset = dragOffset

                    withAnimation(.easeOut(duration: 0.3)) {
                        if currentDragOffset < -threshold && currentPage < totalPages - 1 {
                            currentPage += 1
                        } else if currentDragOffset > threshold && currentPage > 0 {
                            currentPage -= 1
                        }
                        dragOffset = 0
                    }
                }
            }

            return event
        }
    }

    private func stopScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        scrollEndTimer?.invalidate()
        scrollEndTimer = nil
    }
}

// MARK: - Grid Item View

struct GridItemView: View {
    let item: LauncherItem
    let iconSize: CGFloat
    var isMergeTarget: Bool = false
    var isMergeHovering: Bool = false
    var isMergeReady: Bool = false
    var onTap: () -> Void = {}
    var onAppLaunch: () -> Void = {}

    // Cache icon to avoid repeated lookups
    @State private var cachedIcon: NSImage?
    @State private var isHovered = false

    private var backgroundColor: Color {
        if isMergeReady {
            return Color.blue.opacity(0.4)
        } else if isMergeHovering {
            return Color.blue.opacity(0.2)
        } else if isHovered {
            return Color.white.opacity(0.2)
        }
        return Color.clear
    }

    private var borderColor: Color {
        if isMergeReady {
            return Color.blue
        } else if isMergeHovering {
            return Color.blue.opacity(0.5)
        }
        return Color.clear
    }

    private var borderWidth: CGFloat {
        isMergeReady ? 3 : 2
    }

    var body: some View {
        VStack {
            ZStack {
                // Folder preview background (appears during merge hovering)
                if isMergeHovering || isMergeReady {
                    RoundedRectangle(cornerRadius: iconSize * 0.2)
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: iconSize * 1.1, height: iconSize * 1.1)
                }

                Image(nsImage: cachedIcon ?? item.icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isHovered)
            }

            Text(item.name)
                .font(iconSize > 64 ? .callout : .caption)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            switch item {
            case .app(let app):
                app.markUsed()
                NSWorkspace.shared.open(app.url)
                onAppLaunch()
                LauncherPanel.shared.close()
            case .folder:
                onTap()
            }
        }
        .onAppear {
            // Cache icon on appear
            if cachedIcon == nil {
                cachedIcon = item.icon
            }
        }
    }
}

// MARK: - Folder Overlay View

struct FolderOverlayView: View {
    let folder: FolderItem
    let iconSize: CGFloat
    let position: CGPoint
    let onClose: () -> Void
    let onAppLaunch: () -> Void
    let onFolderUpdate: (FolderItem) -> Void

    @State private var folderName: String
    @State private var isEditingName = false

    init(folder: FolderItem, iconSize: CGFloat, position: CGPoint, onClose: @escaping () -> Void, onAppLaunch: @escaping () -> Void, onFolderUpdate: @escaping (FolderItem) -> Void) {
        self.folder = folder
        self.iconSize = iconSize
        self.position = position
        self.onClose = onClose
        self.onAppLaunch = onAppLaunch
        self.onFolderUpdate = onFolderUpdate
        self._folderName = State(initialValue: folder.name)
    }

    private let folderWidth: CGFloat = 320
    private let folderHeight: CGFloat = 280

    var body: some View {
        GeometryReader { geo in
            // Calculate position to keep folder within bounds
            let safeX = min(max(folderWidth / 2 + 20, position.x), geo.size.width - folderWidth / 2 - 20)
            let safeY = min(max(folderHeight / 2 + 80, position.y), geo.size.height - folderHeight / 2 - 20)

            ZStack {
                // Dimmed background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onClose()
                    }

                // Folder content
                VStack(spacing: 12) {
                    // Folder name (editable)
                    if isEditingName {
                        TextField("Folder Name", text: $folderName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 200)
                            .multilineTextAlignment(.center)
                            .onSubmit {
                                isEditingName = false
                                var updated = folder
                                updated.name = folderName
                                onFolderUpdate(updated)
                            }
                    } else {
                        Text(folderName)
                            .font(.headline)
                            .foregroundColor(.white)
                            .onTapGesture {
                                isEditingName = true
                            }
                    }

                    // Apps grid
                    let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(folder.apps) { app in
                            FolderAppItemView(
                                app: app,
                                iconSize: iconSize * 0.7,
                                onTap: {
                                    app.markUsed()
                                    NSWorkspace.shared.open(app.url)
                                    onAppLaunch()
                                    onClose()
                                    LauncherPanel.shared.close()
                                },
                                onRemove: {
                                    var updated = folder
                                    updated.apps.removeAll { $0.url == app.url }
                                    onFolderUpdate(updated)
                                    if updated.apps.isEmpty {
                                        onClose()
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
                .frame(width: folderWidth, height: folderHeight)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.gray.opacity(0.8))
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                )
                .position(x: safeX, y: safeY)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }
}

struct FolderAppItemView: View {
    let app: AppItem
    let iconSize: CGFloat
    let onTap: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack {
            ZStack(alignment: .topLeading) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: iconSize, height: iconSize)
                    .scaleEffect(isHovered ? 1.1 : 1.0)
                    .animation(.easeOut(duration: 0.15), value: isHovered)

                // Remove button on hover
                if isHovered {
                    Button(action: onRemove) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.white)
                            .background(Circle().fill(Color.black.opacity(0.5)))
                    }
                    .buttonStyle(.plain)
                    .offset(x: -5, y: -5)
                }
            }

            Text(app.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(4)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}

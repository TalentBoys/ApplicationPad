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
    @State private var dragTargetIndex: Int?  // Visual target position during drag (no backfill)

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
        // When searching, flatten folders and search all apps (skip empty slots)
        var allApps: [AppItem] = []
        for item in gridItems {
            switch item {
            case .app(let app):
                allApps.append(app)
            case .folder(let folder):
                allApps.append(contentsOf: folder.apps)
            case .empty:
                break  // Skip empty slots
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

    func itemsForPage(_ page: Int) -> [(position: Int, item: LauncherItem)] {
        let start = page * appsPerPage
        let end = min(start + appsPerPage, filteredItems.count)
        guard start < filteredItems.count else { return [] }

        // During drag: show visual reordering without actually moving array items
        // Key: each item knows its visual position, not its array index
        if let _ = draggingItem,
           let fromIndex = dragCurrentIndex,
           let toIndex = dragTargetIndex,
           fromIndex != toIndex {
            // Create position map: for each visual position in this page, which item?
            var result: [(position: Int, item: LauncherItem)] = []

            for visualPos in 0..<appsPerPage {
                let globalVisualPos = start + visualPos

                // Map visual position back to source array index
                let sourceIndex: Int
                if globalVisualPos == toIndex {
                    // Target position shows the dragging item
                    sourceIndex = fromIndex
                } else if fromIndex < toIndex {
                    // Dragging right: positions between from+1..to shift left by 1
                    if globalVisualPos > fromIndex && globalVisualPos <= toIndex {
                        sourceIndex = globalVisualPos  // shifted: visual pos N shows item N+1-1 = N... wait
                    } else if globalVisualPos == fromIndex {
                        continue  // original position is now empty (dragging item moved)
                    } else {
                        sourceIndex = globalVisualPos
                    }
                } else {
                    // Dragging left: positions between to..from-1 shift right by 1
                    if globalVisualPos >= toIndex && globalVisualPos < fromIndex {
                        sourceIndex = globalVisualPos + 1
                    } else if globalVisualPos == fromIndex {
                        continue  // original position is now empty
                    } else {
                        sourceIndex = globalVisualPos
                    }
                }

                if sourceIndex >= 0 && sourceIndex < filteredItems.count {
                    let item = filteredItems[sourceIndex]
                    // Skip empty slots
                    if !item.isEmpty {
                        result.append((position: visualPos, item: item))
                    }
                }
            }

            return result
        }

        // Normal case: return items in order, skipping empty slots
        var result: [(position: Int, item: LauncherItem)] = []
        for (offset, index) in (start..<end).enumerated() {
            let item = filteredItems[index]
            if !item.isEmpty {
                result.append((position: offset, item: item))
            }
        }
        return result
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
                                        ForEach(pageItems, id: \.item.id) { itemData in
                                            let item = itemData.item
                                            let position = itemData.position
                                            let row = position / columnsCount
                                            let col = position % columnsCount
                                            let x = horizontalPadding + cellWidth * (CGFloat(col) + 0.5)
                                            let y = topPadding + cellHeight * (CGFloat(row) + 0.5)
                                            let isDragging = draggingItem?.id == item.id
                                            let isMergeTarget = mergeTargetId == item.id
                                            let isMergeHoveringTarget = isMergeHovering && isMergeTarget
                                            let isMergeReadyTarget = isMergeReady && isMergeTarget
                                            // Check if merge target is a folder (folders should scale up, not show gray background)
                                            let isTargetFolder: Bool = {
                                                if case .folder = item { return true }
                                                return false
                                            }()

                                            let displayX = isDragging ? dragStartPosition.x + draggingOffset.width : x
                                            let displayY = isDragging ? dragStartPosition.y + draggingOffset.height : y

                                            // Find the actual array index for this item
                                            let globalIndex = filteredItems.firstIndex(where: { $0.id == item.id }) ?? (page * appsPerPage + position)

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
                                            // Scale effect: folder targets scale up when merge hovering/ready, app targets scale down when hovering
                                            .scaleEffect(isDragging ? 1.1 : (isMergeReadyTarget ? 1.15 : (isMergeHoveringTarget ? (isTargetFolder ? 1.1 : 0.9) : 1.0)))
                                            .zIndex(isDragging ? 100 : 0)
                                            .opacity(isDragging ? 0.9 : 1.0)
                                            // Only animate position for non-dragging items to avoid flicker
                                            .animation(isDragging ? nil : .easeInOut(duration: 0.2), value: position)
                                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isMergeHoveringTarget)
                                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isMergeReadyTarget)
                                            .position(x: displayX, y: displayY)  // position 放最后，避免坐标系偏移
                                            .highPriorityGesture(
                                                DragGesture(minimumDistance: 15)
                                                    .onChanged { drag in
                                                        if draggingItem == nil && searchText.isEmpty {
                                                            draggingItem = item
                                                            dragCurrentIndex = globalIndex
                                                            dragTargetIndex = globalIndex
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
                        screenSize: geometry.size,
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
            guard let _ = dragCurrentIndex,
                  targetIndex != dragTargetIndex,
                  targetIndex >= 0,
                  targetIndex < gridItems.count else { return }

            // Only update visual target index - don't modify gridItems during drag
            // This prevents backfill from next page
            withAnimation(.easeInOut(duration: 0.2)) {
                dragTargetIndex = targetIndex
            }
        }

        dragStateMachine.onMergeReady = { targetId in
            // Visual feedback is handled by state machine state
            // Haptic feedback for trackpad
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    private func performMerge(draggingItem: LauncherItem, targetItem: LauncherItem, targetIndex: Int, currentIndex: Int) {
        print("📦 performMerge called:")
        print("   draggingItem=\(draggingItem.name) at \(currentIndex)")
        print("   targetItem=\(targetItem.name) at \(targetIndex)")

        // Get apps to add from dragging item
        var appsToAdd: [AppItem] = []
        switch draggingItem {
        case .app(let app):
            appsToAdd.append(app)
        case .folder(let folder):
            appsToAdd.append(contentsOf: folder.apps)
        case .empty:
            break
        }

        // Check if target is already a folder
        if case .folder(var existingFolder) = targetItem {
            // Clear folder icon cache before modifying
            FolderIconCache.shared.clearCache()

            // Add apps to existing folder
            existingFolder.apps.append(contentsOf: appsToAdd)

            withAnimation(.easeInOut(duration: 0.2)) {
                // Replace dragging item with empty slot to preserve page structure
                gridItems[currentIndex] = .empty(UUID())
                // Update folder at its position
                gridItems[targetIndex] = .folder(existingFolder)
            }
        } else {
            // Target is an app, create a new folder
            var appsToMerge: [AppItem] = []

            if case .app(let app) = targetItem {
                appsToMerge.append(app)
            }
            appsToMerge.append(contentsOf: appsToAdd)

            let newFolder = FolderItem(name: "Folder", apps: appsToMerge)

            withAnimation(.easeInOut(duration: 0.2)) {
                // Replace dragging item with empty slot to preserve page structure
                gridItems[currentIndex] = .empty(UUID())
                // Replace target item with new folder
                gridItems[targetIndex] = .folder(newFolder)
            }
        }

        // Clear dragging state
        self.draggingItem = nil
        draggingOffset = .zero
        dragCurrentIndex = nil
        dragTargetIndex = nil
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

        print("🔚 finishDragging: shouldMerge=\(shouldMerge), targetId=\(targetId?.uuidString.prefix(8) ?? "nil")")
        print("   dragCurrentIndex=\(dragCurrentIndex ?? -1), draggingItem=\(draggingItem?.name ?? "nil")")
        print("   dragStateMachine.state=\(dragStateMachine.state)")

        if shouldMerge,
           let targetId = targetId,
           let currentIndex = dragCurrentIndex,
           let dragging = draggingItem,
           let targetIndex = gridItems.firstIndex(where: { $0.id == targetId }) {
            let targetItem = gridItems[targetIndex]
            print("✅ Will performMerge: dragging=\(dragging.name) -> target=\(targetItem.name) at index \(targetIndex)")
            performMerge(draggingItem: dragging, targetItem: targetItem, targetIndex: targetIndex, currentIndex: currentIndex)
            return
        } else {
            print("❌ Merge conditions not met:")
            print("   shouldMerge=\(shouldMerge)")
            print("   targetId=\(targetId?.uuidString.prefix(8) ?? "nil")")
            print("   currentIndex=\(dragCurrentIndex ?? -1)")
            print("   draggingItem=\(draggingItem?.name ?? "nil")")
            if let targetId = targetId {
                let found = gridItems.firstIndex(where: { $0.id == targetId })
                print("   targetIndex in gridItems=\(found ?? -1)")
            }
        }

        // Apply the reorder if target changed
        if let fromIndex = dragCurrentIndex,
           let toIndex = dragTargetIndex,
           let dragging = draggingItem,
           fromIndex != toIndex {
            // Actually modify gridItems now
            gridItems.remove(at: fromIndex)
            let insertIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
            gridItems.insert(dragging, at: min(insertIndex, gridItems.count))
        }

        // Save the final order
        if !gridItems.isEmpty {
            LauncherSettings.saveGridItems(gridItems)
        }

        withAnimation(.easeOut(duration: 0.2)) {
            draggingItem = nil
            draggingOffset = .zero
            dragCurrentIndex = nil
            dragTargetIndex = nil
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

    @State private var isHovered = false

    // Check if target is a folder (for merge animation)
    private var isFolder: Bool {
        if case .folder = item { return true }
        return false
    }

    private var backgroundColor: Color {
        if isHovered {
            return Color.white.opacity(0.2)
        }
        return Color.clear
    }

    var body: some View {
        VStack {
            ZStack {
                // Folder preview background (gray folder style for merge)
                // Only show for app-to-app merge, not for folder targets
                if (isMergeHovering || isMergeReady) && !isFolder {
                    // Use gray folder style instead of blue border
                    RoundedRectangle(cornerRadius: iconSize * 0.2)
                        .fill(Color.gray.opacity(0.4))
                        .frame(width: iconSize * 1.15, height: iconSize * 1.15)
                }

                // Always use item.icon directly - no caching to avoid stale icons
                Image(nsImage: item.icon)
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
            case .empty:
                break  // Empty slots are not tappable
            }
        }
    }
}

// MARK: - Folder Overlay View

struct FolderOverlayView: View {
    let folder: FolderItem
    let iconSize: CGFloat
    let screenSize: CGSize
    let onClose: () -> Void
    let onAppLaunch: () -> Void
    let onFolderUpdate: (FolderItem) -> Void

    @State private var folderName: String
    @State private var isEditingName = false
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0

    // Drag-to-reorder state for folder apps
    @State private var draggingApp: AppItem?
    @State private var draggingOffset: CGSize = .zero
    @State private var dragStartPosition: CGPoint = .zero
    @State private var dragCurrentIndex: Int?
    @State private var dragTargetIndex: Int?

    init(folder: FolderItem, iconSize: CGFloat, screenSize: CGSize, onClose: @escaping () -> Void, onAppLaunch: @escaping () -> Void, onFolderUpdate: @escaping (FolderItem) -> Void) {
        self.folder = folder
        self.iconSize = iconSize
        self.screenSize = screenSize
        self.onClose = onClose
        self.onAppLaunch = onAppLaunch
        self.onFolderUpdate = onFolderUpdate
        self._folderName = State(initialValue: folder.name)
    }

    // Folder grid uses (rows - 2) x (columns - 2)
    private var folderRows: Int { max(1, LauncherSettings.rowsCount - 2) }
    private var folderColumns: Int { max(1, LauncherSettings.columnsCount - 2) }
    private var appsPerPage: Int { folderRows * folderColumns }

    private var totalPages: Int {
        max(1, Int(ceil(Double(folder.apps.count) / Double(appsPerPage))))
    }

    private func appsForPage(_ page: Int) -> [AppItem] {
        let start = page * appsPerPage
        let end = min(start + appsPerPage, folder.apps.count)
        guard start < folder.apps.count else { return [] }
        return Array(folder.apps[start..<end])
    }

    // Get apps for page with visual reordering during drag
    private func appsForPageWithDrag(_ page: Int) -> [(position: Int, app: AppItem)] {
        let start = page * appsPerPage
        let end = min(start + appsPerPage, folder.apps.count)
        guard start < folder.apps.count else { return [] }

        // During drag: show visual reordering
        if let _ = draggingApp,
           let fromIndex = dragCurrentIndex,
           let toIndex = dragTargetIndex,
           fromIndex != toIndex {
            var result: [(position: Int, app: AppItem)] = []

            for visualPos in 0..<appsPerPage {
                let globalVisualPos = start + visualPos
                guard globalVisualPos < folder.apps.count else { continue }

                let sourceIndex: Int
                if globalVisualPos == toIndex {
                    sourceIndex = fromIndex
                } else if fromIndex < toIndex {
                    if globalVisualPos > fromIndex && globalVisualPos <= toIndex {
                        sourceIndex = globalVisualPos
                    } else if globalVisualPos == fromIndex {
                        continue
                    } else {
                        sourceIndex = globalVisualPos
                    }
                } else {
                    if globalVisualPos >= toIndex && globalVisualPos < fromIndex {
                        sourceIndex = globalVisualPos + 1
                    } else if globalVisualPos == fromIndex {
                        continue
                    } else {
                        sourceIndex = globalVisualPos
                    }
                }

                if sourceIndex >= 0 && sourceIndex < folder.apps.count {
                    result.append((position: visualPos, app: folder.apps[sourceIndex]))
                }
            }
            return result
        }

        // Normal case
        var result: [(position: Int, app: AppItem)] = []
        for (offset, index) in (start..<end).enumerated() {
            result.append((position: offset, app: folder.apps[index]))
        }
        return result
    }

    private func finishFolderDragging() {
        // Apply the reorder if target changed
        if let fromIndex = dragCurrentIndex,
           let toIndex = dragTargetIndex,
           fromIndex != toIndex {
            var updated = folder
            let movedApp = updated.apps.remove(at: fromIndex)
            let insertIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
            updated.apps.insert(movedApp, at: min(insertIndex, updated.apps.count))
            onFolderUpdate(updated)
        }

        withAnimation(.easeOut(duration: 0.2)) {
            draggingApp = nil
            draggingOffset = .zero
            dragStartPosition = .zero
            dragCurrentIndex = nil
            dragTargetIndex = nil
        }
    }

    // Calculate cell size based on launcher's cell size
    private var launcherCellWidth: CGFloat {
        (screenSize.width - LauncherSettings.horizontalPadding * 2) / CGFloat(LauncherSettings.columnsCount)
    }
    private var launcherCellHeight: CGFloat {
        let notchHeight: CGFloat = 50
        let searchHeight: CGFloat = 60
        let pageIndicatorHeight: CGFloat = 50
        let availableHeight = screenSize.height - notchHeight - searchHeight - pageIndicatorHeight
        return (availableHeight - LauncherSettings.topPadding - LauncherSettings.bottomPadding) / CGFloat(LauncherSettings.rowsCount)
    }

    var body: some View {
        // Folder size is based on (columns-1) x (rows-1) cells from launcher, plus some padding
        let contentWidth = launcherCellWidth * CGFloat(folderColumns)
        let contentHeight = launcherCellHeight * CGFloat(folderRows)
        let folderPadding: CGFloat = 40
        let titleHeight: CGFloat = 40
        let folderWidth = contentWidth + folderPadding
        let folderHeight = contentHeight + titleHeight + folderPadding

        GeometryReader { geo in
            ZStack {
                // Dimmed background
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onClose()
                    }

                // Folder content - centered
                VStack(spacing: 0) {
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

                    Spacer().frame(height: 12)

                    // Paginated apps grid
                    ZStack {
                        HStack(spacing: 0) {
                            ForEach(0..<totalPages, id: \.self) { page in
                                // Grid for each page - use ZStack with position like launcher
                                ZStack {
                                    let pageApps = appsForPageWithDrag(page)
                                    ForEach(pageApps, id: \.app.id) { itemData in
                                        let app = itemData.app
                                        let position = itemData.position
                                        let row = position / folderColumns
                                        let col = position % folderColumns
                                        let x = launcherCellWidth * (CGFloat(col) + 0.5)
                                        let y = launcherCellHeight * (CGFloat(row) + 0.5)
                                        let isDragging = draggingApp?.id == app.id
                                        let globalIndex = folder.apps.firstIndex(where: { $0.id == app.id }) ?? (page * appsPerPage + position)

                                        let displayX = isDragging ? dragStartPosition.x + draggingOffset.width : x
                                        let displayY = isDragging ? dragStartPosition.y + draggingOffset.height : y

                                        FolderAppItemView(
                                            app: app,
                                            iconSize: iconSize,
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
                                        .scaleEffect(isDragging ? 1.1 : 1.0)
                                        .zIndex(isDragging ? 100 : 0)
                                        .opacity(isDragging ? 0.9 : 1.0)
                                        .animation(isDragging ? nil : .easeInOut(duration: 0.2), value: position)
                                        .position(x: displayX, y: displayY)
                                        .highPriorityGesture(
                                            DragGesture(minimumDistance: 15)
                                                .onChanged { drag in
                                                    if draggingApp == nil {
                                                        draggingApp = app
                                                        dragCurrentIndex = globalIndex
                                                        dragTargetIndex = globalIndex
                                                        dragStartPosition = CGPoint(x: x, y: y)
                                                    }

                                                    if draggingApp?.id == app.id {
                                                        draggingOffset = drag.translation

                                                        // Calculate target index based on drag position
                                                        let dragX = dragStartPosition.x + drag.translation.width
                                                        let dragY = dragStartPosition.y + drag.translation.height
                                                        let targetCol = Int(floor(dragX / launcherCellWidth))
                                                        let targetRow = Int(floor(dragY / launcherCellHeight))

                                                        if targetCol >= 0 && targetCol < folderColumns &&
                                                           targetRow >= 0 && targetRow < folderRows {
                                                            let targetPosInPage = targetRow * folderColumns + targetCol
                                                            let targetIndex = currentPage * appsPerPage + targetPosInPage

                                                            if targetIndex >= 0 && targetIndex < folder.apps.count && targetIndex != dragTargetIndex {
                                                                withAnimation(.easeInOut(duration: 0.2)) {
                                                                    dragTargetIndex = targetIndex
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                                .onEnded { _ in
                                                    if draggingApp?.id == app.id {
                                                        finishFolderDragging()
                                                    }
                                                }
                                        )
                                    }
                                }
                                .frame(width: contentWidth, height: contentHeight)
                            }
                        }
                        .offset(x: -CGFloat(currentPage) * contentWidth + dragOffset)
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                    .frame(width: contentWidth, height: contentHeight)
                    .clipped()
                    .gesture(
                        DragGesture(minimumDistance: 15)
                            .onChanged { value in
                                dragOffset = value.translation.width
                                // Rubber-band effect at edges
                                if currentPage == 0 && dragOffset > 0 {
                                    dragOffset = min(dragOffset, 50)
                                } else if currentPage == totalPages - 1 && dragOffset < 0 {
                                    dragOffset = max(dragOffset, -50)
                                }
                            }
                            .onEnded { value in
                                let threshold = contentWidth * 0.2
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    if value.translation.width < -threshold && currentPage < totalPages - 1 {
                                        currentPage += 1
                                    } else if value.translation.width > threshold && currentPage > 0 {
                                        currentPage -= 1
                                    }
                                    dragOffset = 0
                                }
                            }
                    )

                    // Page indicator
                    if totalPages > 1 {
                        HStack(spacing: 6) {
                            ForEach(0..<totalPages, id: \.self) { page in
                                Circle()
                                    .fill(page == currentPage ? Color.white : Color.white.opacity(0.4))
                                    .frame(width: 6, height: 6)
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            currentPage = page
                                        }
                                    }
                            }
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(folderPadding / 2)
                .frame(width: folderWidth, height: folderHeight + (totalPages > 1 ? 20 : 0))
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.clear)
                        .background(
                            VisualEffectView()
                                .clipShape(RoundedRectangle(cornerRadius: 20))
                        )
                )
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
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
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovered)

            Text(app.name)
                .font(.caption)
                .foregroundColor(.white)
                .lineLimit(1)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.white.opacity(0.2) : Color.clear)
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onTap()
        }
    }
}

//
//  AppGridView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI
import LauncherCore

struct AppGridView: View {
    @State private var searchText = ""
    @State private var apps = AppScanner.scan()
    @State private var keyMonitor = KeyEventMonitor()
    @State private var currentPage = LauncherSettings.lastPage
    @State private var dragOffset: CGFloat = 0
    @State private var scrollMonitor: Any?
    @State private var pageWidth: CGFloat = 0
    @State private var scrollEndTimer: Timer?
    @FocusState private var isSearchFocused: Bool

    // Grid state manager (preview/stable dual-layer model)
    @StateObject private var gridState = GridState()

    // Drag-to-reorder state
    @State private var draggingItem: LauncherItem?
    @State private var draggingOffset: CGSize = .zero
    @State private var dragCurrentIndex: Int?
    @State private var dragStartPosition: CGPoint = .zero
    @State private var dragAccumulatedOffset: CGSize = .zero  // Compensate for dragStartPosition changes
    @State private var dragMouseOffset: CGSize = .zero  // Mouse click position relative to icon center
    @State private var isDraggingPage: Bool = false
    @State private var dragEdgePageChanged: Bool = false  // Prevent multiple page changes during edge drag
    @State private var dragEdgeStartTime: Date? = nil  // Track when edge was first touched for auto-repeat

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

    // State for dragging into open folder
    @State private var dragIntoFolderTargetIndex: Int?  // Target position inside folder
    @State private var dragIntoFolderTargetId: UUID?    // The folder being dragged into

    var columnsCount: Int { LauncherSettings.columnsCount }
    var rowsCount: Int { LauncherSettings.rowsCount }
    var appsPerPage: Int { LauncherSettings.appsPerPage }
    var iconSize: CGFloat { LauncherSettings.iconSize }
    var horizontalPadding: CGFloat { LauncherSettings.horizontalPadding }
    var topPadding: CGFloat { LauncherSettings.topPadding }
    var bottomPadding: CGFloat { LauncherSettings.bottomPadding }

    /// The items to display (from gridState, which handles preview/stable)
    var gridItems: [LauncherItem] {
        gridState.items
    }

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
        gridState.setStable(LauncherSettings.applyCustomOrder(to: apps))
    }

    var totalPages: Int {
        max(1, Int(ceil(Double(filteredItems.count) / Double(appsPerPage))))
    }

    func itemsForPage(_ page: Int) -> [(position: Int, item: LauncherItem)] {
        let start = page * appsPerPage
        let end = min(start + appsPerPage, filteredItems.count)
        guard start < filteredItems.count else { return [] }

        // gridState.items already returns preview state during drag
        // So we just return items in order, skipping empty slots
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
                                            // Scale effect: all merge targets scale up when hovering/ready (folder preview effect)
                                            .scaleEffect(isDragging ? 1.1 : (isMergeReadyTarget ? 1.15 : (isMergeHoveringTarget ? 1.1 : 1.0)))
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
                                                            dragStartPosition = CGPoint(x: x, y: y)
                                                            dragAccumulatedOffset = .zero
                                                            // Record mouse click position relative to icon center
                                                            // This ensures the icon stays "attached" to where the user clicked
                                                            dragMouseOffset = CGSize(
                                                                width: drag.startLocation.x - x,
                                                                height: drag.startLocation.y - y
                                                            )
                                                            // Start preview mode: preview = stable
                                                            gridState.setLayoutForLogging(columnsCount: columnsCount, rowsCount: rowsCount)
                                                            gridState.enableLayoutLogging = true
                                                            gridState.startPreview()
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

                                                            // screenX is the actual mouse position without page compensation
                                                            // Used for edge detection to prevent page change loops
                                                            let screenX = dragStartPosition.x + drag.translation.width + dragMouseOffset.width

                                                            updateDragPosition(
                                                                dragX: dragX,
                                                                dragY: dragY,
                                                                screenX: screenX,
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
                        externalDraggingItem: draggingItem,
                        externalDraggingOffset: draggingOffset,
                        externalDragStartPosition: dragStartPosition,
                        onClose: {
                            // If we're dragging into folder, don't close
                            if draggingItem != nil && dragIntoFolderTargetId != nil {
                                return
                            }
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                openFolder = nil
                            }
                            dragIntoFolderTargetId = nil
                            dragIntoFolderTargetIndex = nil
                        },
                        onAppLaunch: {
                            apps = AppScanner.scan()
                            refreshGridItems()
                        },
                        onFolderUpdate: { updatedFolder in
                            updateFolder(updatedFolder)
                            // Also update openFolder so FolderContentView sees the changes
                            openFolder = updatedFolder
                        },
                        onDragIntoFolder: { targetIndex in
                            dragIntoFolderTargetIndex = targetIndex
                        },
                        onDragOutOfFolder: { app, dragPosition in
                            handleDragOutOfFolder(app: app, dragPosition: dragPosition, folder: folder, geo: geometry)
                        }
                    )
                }
            }
        }
        .onAppear {
            refreshGridItems()
            // Ensure currentPage is within valid range
            if currentPage >= totalPages {
                currentPage = max(0, totalPages - 1)
            }
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
        if let index = gridState.stableItems.firstIndex(where: {
            if case .folder(let f) = $0 { return f.id == updatedFolder.id }
            return false
        }) {
            if updatedFolder.apps.isEmpty {
                gridState.removeFromStable(at: index)
            } else if updatedFolder.apps.count == 1 {
                // Folder has only one app, convert back to single app
                gridState.updateStable(at: index, with: .app(updatedFolder.apps[0]))
            } else {
                gridState.updateStable(at: index, with: .folder(updatedFolder))
            }
            LauncherSettings.saveGridItems(gridState.stableItems)
        }
    }

    private func focusSearchField() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isSearchFocused = true
        }
    }

    private func closeLauncher() {
        LauncherSettings.lastPage = currentPage
        LauncherPanel.shared.close()
        searchText = ""
        openFolder = nil
    }

    private func handleDragOutOfFolder(app: AppItem, dragPosition: CGPoint, folder: FolderItem, geo: GeometryProxy) {
        print("📤 App dragged out of folder: \(app.name) at position \(dragPosition)")

        // Remove app from folder
        var updatedFolder = folder
        updatedFolder.apps.removeAll { $0.id == app.id }

        // Update the folder in gridState (stable)
        if let folderIndex = gridState.stableItems.firstIndex(where: {
            if case .folder(let f) = $0 { return f.id == folder.id }
            return false
        }) {
            FolderIconCache.shared.clearCache()

            if updatedFolder.apps.isEmpty {
                gridState.removeFromStable(at: folderIndex)
            } else if updatedFolder.apps.count == 1 {
                gridState.updateStable(at: folderIndex, with: .app(updatedFolder.apps[0]))
            } else {
                gridState.updateStable(at: folderIndex, with: .folder(updatedFolder))
            }
        }

        // Close folder
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            openFolder = nil
        }

        // Calculate cell dimensions for main grid
        let screenHeight = geo.size.height
        let notchHeight: CGFloat = 50
        let searchHeight: CGFloat = 60
        let pageIndicatorHeight: CGFloat = totalPages > 1 ? 50 : 0
        let availableHeight = screenHeight - notchHeight - searchHeight - pageIndicatorHeight - topPadding - bottomPadding
        let cellWidth = (geo.size.width - horizontalPadding * 2) / CGFloat(columnsCount)
        let cellHeight = (availableHeight + topPadding + bottomPadding - topPadding - bottomPadding) / CGFloat(rowsCount)

        // Calculate grid position from drag position
        let col = Int(floor((dragPosition.x - horizontalPadding) / cellWidth))
        let row = Int(floor((dragPosition.y - notchHeight - searchHeight - topPadding) / cellHeight))

        // Calculate target index
        let validCol = max(0, min(col, columnsCount - 1))
        let validRow = max(0, min(row, rowsCount - 1))
        let targetIndexInPage = validRow * columnsCount + validCol
        let targetIndex = currentPage * appsPerPage + targetIndexInPage

        // Start dragging the app in the main grid
        draggingItem = .app(app)
        dragStartPosition = dragPosition
        draggingOffset = .zero
        dragAccumulatedOffset = .zero
        dragMouseOffset = .zero

        // Find or create position for the app - insert into stable first
        let insertIndex = max(0, min(targetIndex, gridState.stableItems.count))
        var newStable = gridState.stableItems
        newStable.insert(.app(app), at: insertIndex)
        gridState.setStable(newStable)

        // Now start preview mode for further dragging
        gridState.startPreview()
        dragCurrentIndex = insertIndex

        // Start the drag state machine
        dragStateMachine.startDrag()
        setupStateMachineCallbacks(cellWidth: cellWidth, cellHeight: cellHeight)

        LauncherSettings.saveGridItems(gridState.stableItems)
    }

    private func updateDragPosition(dragX: CGFloat, dragY: CGFloat, screenX: CGFloat, cellWidth: CGFloat, cellHeight: CGFloat) {
        guard let currentIndex = dragCurrentIndex, let dragging = draggingItem else { return }

        // Check for edge drag to change page
        // Use screenX (actual mouse position) instead of dragX (compensated position)
        // This prevents page change loops caused by dragAccumulatedOffset compensation
        let edgeThreshold: CGFloat = 50  // pixels from edge to trigger page change
        let edgeRepeatDelay: TimeInterval = 2.0  // seconds to wait before allowing another page change

        let isNearLeftEdge = screenX < edgeThreshold && currentPage > 0
        let isNearRightEdge = screenX > pageWidth - edgeThreshold && currentPage < totalPages - 1
        let isNearEdge = isNearLeftEdge || isNearRightEdge

        if isNearEdge {
            let now = Date()

            var shouldChangePage = false
            var pageDirection: Int = 0  // -1 for left, +1 for right

            if !dragEdgePageChanged {
                // First touch on edge - trigger page change immediately
                dragEdgePageChanged = true
                dragEdgeStartTime = now
                shouldChangePage = true
                pageDirection = isNearLeftEdge ? -1 : 1
            } else if let startTime = dragEdgeStartTime {
                // Already changed page, check if delay has passed for auto-repeat
                if now.timeIntervalSince(startTime) >= edgeRepeatDelay {
                    // Reset for another page change
                    dragEdgeStartTime = now
                    shouldChangePage = true
                    if isNearLeftEdge && currentPage > 0 {
                        pageDirection = -1
                    } else if isNearRightEdge && currentPage < totalPages - 1 {
                        pageDirection = 1
                    }
                }
            }

            if shouldChangePage && pageDirection != 0 {
                let newPage = currentPage + pageDirection

                // Update dragStartPosition to compensate for page change
                // This keeps the visual position consistent
                dragAccumulatedOffset.width -= CGFloat(pageDirection) * pageWidth

                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage = newPage
                }
            }
        } else {
            // Not near edge - reset flags to allow next edge trigger
            dragEdgePageChanged = false
            dragEdgeStartTime = nil
        }

        // Create layout params for state machine
        let layout = GridLayoutParams(
            columnsCount: columnsCount,
            rowsCount: rowsCount,
            appsPerPage: appsPerPage,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            iconSize: iconSize,
            horizontalPadding: horizontalPadding,
            topPadding: topPadding
        )

        // Use state machine for hit detection and state management
        dragStateMachine.updateDrag(
            position: CGPoint(x: dragX, y: dragY),
            gridItems: gridState.items,
            draggingItemId: dragging.id,
            sourceIndex: currentIndex,
            layout: layout,
            currentPage: currentPage
        )
    }

    private func setupStateMachineCallbacks(cellWidth: CGFloat, cellHeight: CGFloat) {
        // Create layout params for callbacks
        let layout = GridLayoutParams(
            columnsCount: columnsCount,
            rowsCount: rowsCount,
            appsPerPage: appsPerPage,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            iconSize: iconSize,
            horizontalPadding: horizontalPadding,
            topPadding: topPadding
        )

        dragStateMachine.onOperationChanged = { [self] operation, targetCell, sourceIndex in
            guard targetCell != nil else { return }

            // Apply the operation to preview
            // Note: sourceIndex is always the original position in stable, it never changes during drag
            gridState.applyOperation(
                operation: operation,
                targetCell: targetCell,
                sourceIndex: sourceIndex,
                layout: layout
            )
            // Don't update dragCurrentIndex - it always refers to the original stable position
        }

        dragStateMachine.onMergeReady = { targetId in
            // Visual feedback is handled by state machine state
            // Haptic feedback for trackpad
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }

        dragStateMachine.onFolderOpen = { [self] targetId in
            // Find the folder being dragged over
            guard let folderIndex = gridState.items.firstIndex(where: { $0.id == targetId }),
                  case .folder(let folder) = gridState.items[folderIndex] else { return }

            print("📂 Opening folder for drag-into: \(folder.name)")

            // Store the folder we're dragging into
            dragIntoFolderTargetId = targetId
            dragIntoFolderTargetIndex = 0  // Default to first position

            // Open the folder
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                openFolder = folder
            }
        }
    }

    private func performMerge(draggingItem: LauncherItem, targetId: UUID, currentIndex: Int) {
        guard let targetIndex = gridState.items.firstIndex(where: { $0.id == targetId }) else {
            print("❌ performMerge: target not found")
            return
        }

        let targetItem = gridState.items[targetIndex]
        print("📦 performMerge called:")
        print("   draggingItem=\(draggingItem.name) at \(currentIndex)")
        print("   targetItem=\(targetItem.name) at \(targetIndex)")

        // Clear folder icon cache before modifying
        FolderIconCache.shared.clearCache()

        // Perform merge on preview
        gridState.merge(sourceIndex: currentIndex, intoTargetIndex: targetIndex)

        // Clear dragging state
        self.draggingItem = nil
        draggingOffset = .zero
        dragCurrentIndex = nil
        dragStartPosition = .zero
        dragAccumulatedOffset = .zero
        dragMouseOffset = .zero
        dragStateMachine.reset()

        // Commit and save
        gridState.commitPreview()
        LauncherSettings.saveGridItems(gridState.stableItems)
    }

    private func finishDragging() {
        // Check if we're dragging into an open folder
        if let folderId = dragIntoFolderTargetId,
           let targetInsertIndex = dragIntoFolderTargetIndex,
           let folderIndex = gridState.items.firstIndex(where: { $0.id == folderId }),
           case .folder(var folder) = gridState.items[folderIndex],
           let currentIndex = dragCurrentIndex,
           let dragging = draggingItem {

            print("📂 Dropping into folder at position \(targetInsertIndex)")

            // Get apps to add from dragging item
            var appsToAdd: [AppItem] = []
            switch dragging {
            case .app(let app):
                appsToAdd.append(app)
            case .folder(let draggedFolder):
                appsToAdd.append(contentsOf: draggedFolder.apps)
            case .empty:
                break
            }

            // Insert apps at target position
            let insertAt = min(targetInsertIndex, folder.apps.count)
            folder.apps.insert(contentsOf: appsToAdd, at: insertAt)

            // Clear folder icon cache before modifying
            FolderIconCache.shared.clearCache()

            // Replace dragging item with empty slot on preview
            gridState.replace(at: currentIndex, with: .empty(UUID()))
            gridState.replace(at: folderIndex, with: .folder(folder))

            // Close folder
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                openFolder = nil
            }

            // Commit and save
            gridState.commitPreview()
            LauncherSettings.saveGridItems(gridState.stableItems)

            // Clear drag state
            draggingItem = nil
            draggingOffset = .zero
            dragCurrentIndex = nil
            dragStartPosition = .zero
            dragAccumulatedOffset = .zero
            dragMouseOffset = .zero
            dragEdgePageChanged = false
            dragEdgeStartTime = nil
            dragIntoFolderTargetId = nil
            dragIntoFolderTargetIndex = nil
            dragStateMachine.reset()
            return
        }

        // Ask state machine if we should merge
        let (shouldMerge, targetId, _) = dragStateMachine.endDrag()

        print("🔚 finishDragging: shouldMerge=\(shouldMerge), targetId=\(targetId?.uuidString.prefix(8) ?? "nil")")
        print("   dragCurrentIndex=\(dragCurrentIndex ?? -1), draggingItem=\(draggingItem?.name ?? "nil")")
        print("   gridState.previewHasChanges=\(gridState.previewHasChanges)")

        if shouldMerge,
           let targetId = targetId,
           let currentIndex = dragCurrentIndex,
           let dragging = draggingItem {
            print("✅ Will performMerge: dragging=\(dragging.name) -> targetId=\(targetId.uuidString.prefix(8))")
            performMerge(draggingItem: dragging, targetId: targetId, currentIndex: currentIndex)
            return
        }

        // Check if we have changes to commit
        if gridState.previewHasChanges {
            // Commit the preview to stable
            gridState.commitPreview()
            LauncherSettings.saveGridItems(gridState.stableItems)
            print("✅ Committed preview changes")
        } else {
            // No changes, cancel preview (revert to stable)
            gridState.cancelPreview()
            print("↩️ Cancelled preview (no changes)")
        }

        // Clear drag state
        draggingItem = nil
        draggingOffset = .zero
        dragCurrentIndex = nil
        dragStartPosition = .zero
        dragAccumulatedOffset = .zero
        dragMouseOffset = .zero
        dragEdgePageChanged = false
        dragEdgeStartTime = nil
        dragIntoFolderTargetId = nil
        dragIntoFolderTargetIndex = nil
    }

    private func startScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            // Skip if folder is open - let folder handle its own scrolling
            if openFolder != nil {
                return event
            }

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
                    // Use gray folder style with border (matching folder merge effect)
                    RoundedRectangle(cornerRadius: iconSize * 0.2)
                        .fill(Color.gray.opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: iconSize * 0.2)
                                .stroke(Color.white.opacity(0.6), lineWidth: 2)
                        )
                        .frame(width: iconSize * 1.15, height: iconSize * 1.15)
                }

                // Border effect for folder targets during merge
                if (isMergeHovering || isMergeReady) && isFolder {
                    RoundedRectangle(cornerRadius: iconSize * 0.2)
                        .stroke(Color.white.opacity(0.6), lineWidth: 2)
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
    let externalDraggingItem: LauncherItem?
    let externalDraggingOffset: CGSize
    let externalDragStartPosition: CGPoint
    let onClose: () -> Void
    let onAppLaunch: () -> Void
    let onFolderUpdate: (FolderItem) -> Void
    let onDragIntoFolder: (Int) -> Void
    let onDragOutOfFolder: (AppItem, CGPoint) -> Void  // Called when dragging app out of folder

    @State private var folderName: String
    @State private var isEditingName = false
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var scrollMonitor: Any?
    @State private var scrollEndTimer: Timer?

    // Drag-to-reorder state for folder apps
    @State private var draggingApp: AppItem?
    @State private var draggingOffset: CGSize = .zero
    @State private var dragStartPosition: CGPoint = .zero
    @State private var dragCurrentIndex: Int?
    @State private var dragTargetIndex: Int?

    // Track external drag position inside folder
    @State private var externalDragTargetIndex: Int?

    init(folder: FolderItem, iconSize: CGFloat, screenSize: CGSize,
         externalDraggingItem: LauncherItem? = nil,
         externalDraggingOffset: CGSize = .zero,
         externalDragStartPosition: CGPoint = .zero,
         onClose: @escaping () -> Void, onAppLaunch: @escaping () -> Void,
         onFolderUpdate: @escaping (FolderItem) -> Void,
         onDragIntoFolder: @escaping (Int) -> Void = { _ in },
         onDragOutOfFolder: @escaping (AppItem, CGPoint) -> Void = { _, _ in }) {
        self.folder = folder
        self.iconSize = iconSize
        self.screenSize = screenSize
        self.externalDraggingItem = externalDraggingItem
        self.externalDraggingOffset = externalDraggingOffset
        self.externalDragStartPosition = externalDragStartPosition
        self.onClose = onClose
        self.onAppLaunch = onAppLaunch
        self.onFolderUpdate = onFolderUpdate
        self.onDragIntoFolder = onDragIntoFolder
        self.onDragOutOfFolder = onDragOutOfFolder
        self._folderName = State(initialValue: folder.name)
    }

    // Folder grid uses (rows - 2) x (columns - 2)
    private var folderRows: Int { max(1, LauncherSettings.rowsCount - 2) }
    private var folderColumns: Int { max(1, LauncherSettings.columnsCount - 2) }
    private var appsPerPage: Int { folderRows * folderColumns }

    private var totalPages: Int {
        let pages = max(1, Int(ceil(Double(folder.apps.count) / Double(appsPerPage))))
        print("📁 Folder pagination: apps=\(folder.apps.count), rows=\(folderRows), cols=\(folderColumns), perPage=\(appsPerPage), totalPages=\(pages)")
        return pages
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
        guard start < folder.apps.count else {
            print("📁 appsForPageWithDrag(\(page)): empty - start=\(start) >= count=\(folder.apps.count)")
            return []
        }

        // During drag: show visual reordering
        if let dragging = draggingApp,
           let fromIndex = dragCurrentIndex,
           let toIndex = dragTargetIndex,
           fromIndex != toIndex {
            var result: [(position: Int, app: AppItem)] = []

            for visualPos in 0..<appsPerPage {
                let globalVisualPos = start + visualPos
                guard globalVisualPos < folder.apps.count else { continue }

                let sourceIndex: Int
                if globalVisualPos == toIndex {
                    // Target position shows the dragging item
                    sourceIndex = fromIndex
                } else if fromIndex < toIndex {
                    // Dragging right: items between from+1..to shift left by 1
                    if globalVisualPos >= fromIndex && globalVisualPos < toIndex {
                        sourceIndex = globalVisualPos + 1
                    } else {
                        sourceIndex = globalVisualPos
                    }
                } else {
                    // Dragging left: items between to+1..from shift right by 1
                    if globalVisualPos > toIndex && globalVisualPos <= fromIndex {
                        sourceIndex = globalVisualPos - 1
                    } else {
                        sourceIndex = globalVisualPos
                    }
                }

                if sourceIndex >= 0 && sourceIndex < folder.apps.count {
                    result.append((position: visualPos, app: folder.apps[sourceIndex]))
                }
            }
            print("📁 appsForPageWithDrag(\(page)): drag mode, returning \(result.count) items")
            return result
        }

        // Normal case
        var result: [(position: Int, app: AppItem)] = []
        for (offset, index) in (start..<end).enumerated() {
            result.append((position: offset, app: folder.apps[index]))
        }
        print("📁 appsForPageWithDrag(\(page)): normal mode, start=\(start), end=\(end), returning \(result.count) items")
        return result
    }

    private func finishFolderDragging() {
        // Apply the reorder if target changed
        if let fromIndex = dragCurrentIndex,
           let toIndex = dragTargetIndex,
           fromIndex != toIndex {
            var updated = folder
            let movedApp = updated.apps.remove(at: fromIndex)
            // After removal, indices shift: if toIndex > fromIndex, target is now at toIndex-1
            let insertIndex = toIndex > fromIndex ? toIndex - 1 : toIndex
            updated.apps.insert(movedApp, at: min(insertIndex, updated.apps.count))
            onFolderUpdate(updated)
            print("📁 Folder reorder: \(fromIndex) -> \(toIndex), insertAt: \(insertIndex)")
        } else {
            print("📁 Folder drag ended without reorder: from=\(String(describing: dragCurrentIndex)), to=\(String(describing: dragTargetIndex))")
        }

        // Clear drag state first (without animation), then update folder causes re-render
        draggingApp = nil
        draggingOffset = .zero
        dragStartPosition = .zero
        dragCurrentIndex = nil
        dragTargetIndex = nil
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
                // Dimmed background - no animation, appears/disappears instantly
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                        onClose()
                    }

                // Folder content - centered, with animation
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
                                        // Animate position changes for non-dragging items
                                        .animation(isDragging ? nil : .easeInOut(duration: 0.2), value: globalIndex)
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

                                                        // Calculate drag position in folder local coordinates
                                                        let dragX = dragStartPosition.x + drag.translation.width
                                                        let dragY = dragStartPosition.y + drag.translation.height

                                                        // Check if dragged outside folder bounds
                                                        let margin: CGFloat = 30  // Some margin before triggering exit
                                                        let isOutside = dragX < -margin ||
                                                                       dragX > contentWidth + margin ||
                                                                       dragY < -margin ||
                                                                       dragY > contentHeight + margin

                                                        if isOutside {
                                                            // Calculate screen position for the drag
                                                            let folderCenterX = geo.size.width / 2
                                                            let folderCenterY = geo.size.height / 2
                                                            let folderContentLeft = folderCenterX - contentWidth / 2
                                                            let folderContentTop = folderCenterY - (contentHeight + titleHeight + folderPadding) / 2 + titleHeight + folderPadding / 2 + 12

                                                            let screenDragX = folderContentLeft + dragX
                                                            let screenDragY = folderContentTop + dragY

                                                            // Clear drag state
                                                            let draggedApp = app
                                                            draggingApp = nil
                                                            draggingOffset = .zero
                                                            dragCurrentIndex = nil
                                                            dragTargetIndex = nil

                                                            // Notify parent to handle drag out of folder
                                                            onDragOutOfFolder(draggedApp, CGPoint(x: screenDragX, y: screenDragY))
                                                            return
                                                        }

                                                        // Calculate target index based on drag position
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
                // Folder content animation (expand/collapse)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        // No transition on the container - the dimmed background appears instantly
        .onAppear {
            startFolderScrollMonitor()
        }
        .onDisappear {
            stopFolderScrollMonitor()
        }
        .onChange(of: externalDraggingOffset) { _, newOffset in
            // Track external drag position and calculate target index inside folder
            guard externalDraggingItem != nil else { return }

            // Calculate the drag position relative to folder content
            let dragX = externalDragStartPosition.x + newOffset.width
            let dragY = externalDragStartPosition.y + newOffset.height

            // Folder is centered on screen
            let folderCenterX = screenSize.width / 2
            let folderCenterY = screenSize.height / 2
            let contentWidth = launcherCellWidth * CGFloat(folderColumns)
            let contentHeight = launcherCellHeight * CGFloat(folderRows)
            let folderPadding: CGFloat = 40
            let titleHeight: CGFloat = 40

            // Calculate folder content bounds
            let folderLeft = folderCenterX - contentWidth / 2
            let folderTop = folderCenterY - (contentHeight + titleHeight + folderPadding) / 2 + titleHeight + folderPadding / 2 + 12

            // Convert drag position to folder local coordinates
            let localX = dragX - folderLeft
            let localY = dragY - folderTop

            // Calculate target cell
            let targetCol = Int(floor(localX / launcherCellWidth))
            let targetRow = Int(floor(localY / launcherCellHeight))

            if targetCol >= 0 && targetCol < folderColumns &&
               targetRow >= 0 && targetRow < folderRows {
                let targetPosInPage = targetRow * folderColumns + targetCol
                let targetIndex = currentPage * appsPerPage + targetPosInPage

                // Clamp to valid range (0 to folder.apps.count)
                let clampedIndex = max(0, min(targetIndex, folder.apps.count))

                if clampedIndex != externalDragTargetIndex {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        externalDragTargetIndex = clampedIndex
                    }
                    onDragIntoFolder(clampedIndex)
                }
            }
        }
    }

    private func startFolderScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [self] event in
            if event.momentumPhase != [] {
                return event
            }

            // Only handle if folder has multiple pages
            guard totalPages > 1 else { return event }

            let invert: CGFloat = LauncherSettings.invertScroll ? -1 : 1
            let sensitivity = LauncherSettings.scrollSensitivity

            let deltaX = event.scrollingDeltaX * invert * sensitivity
            let deltaY = event.scrollingDeltaY * invert * sensitivity

            let delta = deltaX - deltaY

            guard abs(delta) > 0.1 else { return event }

            let contentWidth = launcherCellWidth * CGFloat(folderColumns)
            dragOffset += delta

            let maxOffset = contentWidth > 0 ? contentWidth : 500
            dragOffset = max(-maxOffset, min(maxOffset, dragOffset))

            if currentPage == 0 && dragOffset > 0 {
                dragOffset = min(dragOffset, 50)
            } else if currentPage == totalPages - 1 && dragOffset < 0 {
                dragOffset = max(dragOffset, -50)
            }

            scrollEndTimer?.invalidate()
            scrollEndTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: false) { _ in
                DispatchQueue.main.async {
                    let threshold = contentWidth * 0.15
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

            return nil  // Consume the event so it doesn't propagate
        }
    }

    private func stopFolderScrollMonitor() {
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
            scrollMonitor = nil
        }
        scrollEndTimer?.invalidate()
        scrollEndTimer = nil
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

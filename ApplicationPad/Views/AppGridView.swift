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
    @State private var dragEdgeStartTime: Date? = nil  // Cooldown timer: last page change time (2s delay between changes)
    @State private var dragStartPage: Int = 0  // Page where drag started (for calculating true screen position)

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

    // State for dragging out of folder (needs mouse tracking)
    @State private var isDraggingFromFolder: Bool = false
    @State private var mouseTrackingMonitor: Any?

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

        // IMPORTANT: If we're dragging an item and this is the page where drag started,
        // ensure the dragging item is included (even if preview moved it elsewhere).
        // This keeps the DragGesture alive.
        // Skip this if dragging from folder - the item is already in filteredItems.
        if let dragging = draggingItem, page == dragStartPage, !isDraggingFromFolder {
            let alreadyIncluded = result.contains { $0.item.id == dragging.id }
            if !alreadyIncluded {
                // Add it at position 0 (actual position doesn't matter since it's invisible)
                result.append((position: 0, item: dragging))
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
                            // Page content (scrolls with page changes)
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
                                            .scaleEffect(isMergeReadyTarget ? 1.15 : (isMergeHoveringTarget ? 1.1 : 1.0))
                                            // Hide the item visually when dragging (it's rendered in overlay instead)
                                            // but keep it in the view hierarchy so DragGesture continues to work
                                            .opacity(isDragging ? 0 : 1.0)
                                            // Only animate position for non-dragging items to avoid flicker
                                            .animation(.easeInOut(duration: 0.2), value: position)
                                            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isMergeHoveringTarget)
                                            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: isMergeReadyTarget)
                                            .position(x: x, y: y)
                                            .highPriorityGesture(
                                                DragGesture(minimumDistance: 15)
                                                    .onChanged { drag in
                                                        if draggingItem == nil && searchText.isEmpty {
                                                            draggingItem = item
                                                            dragCurrentIndex = globalIndex
                                                            dragStartPosition = CGPoint(x: x, y: y)
                                                            dragAccumulatedOffset = .zero
                                                            dragStartPage = currentPage  // Remember which page we started on
                                                            dragEdgeStartTime = nil  // Reset cooldown for new drag
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

                                                        // Don't check item.id - during drag, positions change
                                                        // and the view's item might differ from draggingItem
                                                        if draggingItem != nil {
                                                            // Apply accumulated offset and mouse offset to keep icon attached to cursor
                                                            draggingOffset = CGSize(
                                                                width: drag.translation.width + dragAccumulatedOffset.width + dragMouseOffset.width,
                                                                height: drag.translation.height + dragAccumulatedOffset.height + dragMouseOffset.height
                                                            )

                                                            // Calculate actual screen position by compensating for page changes
                                                            // drag.translation is relative to the view's original position
                                                            // When page changes, the view moves but translation doesn't reset
                                                            let pageOffset = CGFloat(currentPage - dragStartPage) * pageWidth
                                                            let screenX = dragStartPosition.x + drag.translation.width + dragMouseOffset.width - pageOffset
                                                            let screenY = dragStartPosition.y + drag.translation.height + dragMouseOffset.height

                                                            updateDragPosition(
                                                                localX: screenX,
                                                                localY: screenY,
                                                                cellWidth: cellWidth,
                                                                cellHeight: cellHeight
                                                            )
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        // Don't check item.id - during drag, positions change and
                                                        // the item at this view might be different from draggingItem
                                                        if draggingItem != nil {
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

                            // Dragging item overlay - rendered outside page system so it's always visible
                            if let dragging = draggingItem {
                                let displayX = dragStartPosition.x + draggingOffset.width
                                let displayY = dragStartPosition.y + draggingOffset.height

                                GridItemView(
                                    item: dragging,
                                    iconSize: iconSize,
                                    isMergeTarget: false,
                                    isMergeHovering: false,
                                    isMergeReady: false,
                                    onTap: {},
                                    onAppLaunch: {}
                                )
                                .scaleEffect(1.1)
                                .opacity(0.9)
                                .position(x: displayX, y: displayY)
                                .zIndex(100)
                                .allowsHitTesting(false)  // Don't intercept touches
                            }
                        }
                        .contentShape(Rectangle())
                        .simultaneousGesture(
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
        // Need longer delay to ensure window is fully ready and key
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
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
        print("📤 App dragged out of folder: \(app.name) at screen position \(dragPosition)")

        // Remove app from folder
        var updatedFolder = folder
        updatedFolder.slots.removeAll { $0.id == app.id }
        updatedFolder.compact()

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

        // Calculate grid area offset from screen top
        // The grid is below: notch + search bar
        let notchHeight: CGFloat = 50
        let searchHeight: CGFloat = 60

        // Convert screen coordinates to grid-local coordinates
        // dragPosition is in screen coordinates (0,0 at top-left of screen)
        // Grid overlay is positioned relative to the grid area (below notch + search)
        let gridLocalX = dragPosition.x
        let gridLocalY = dragPosition.y - notchHeight - searchHeight

        print("📤 Converted to grid-local position: (\(gridLocalX), \(gridLocalY))")

        // Calculate cell dimensions for main grid
        let screenHeight = geo.size.height
        let pageIndicatorHeight: CGFloat = totalPages > 1 ? 50 : 0
        let availableHeight = screenHeight - notchHeight - searchHeight - pageIndicatorHeight - topPadding - bottomPadding
        let cellWidth = (geo.size.width - horizontalPadding * 2) / CGFloat(columnsCount)
        let cellHeight = (availableHeight + topPadding + bottomPadding - topPadding - bottomPadding) / CGFloat(rowsCount)

        // Calculate grid position from grid-local position
        let col = Int(floor((gridLocalX - horizontalPadding) / cellWidth))
        let row = Int(floor((gridLocalY - topPadding) / cellHeight))

        // Calculate target index
        let validCol = max(0, min(col, columnsCount - 1))
        let validRow = max(0, min(row, rowsCount - 1))
        let targetIndexInPage = validRow * columnsCount + validCol
        let targetIndex = currentPage * appsPerPage + targetIndexInPage

        // Start dragging the app in the main grid
        // Use grid-local coordinates for dragStartPosition (matches overlay coordinate system)
        draggingItem = .app(app)
        dragStartPosition = CGPoint(x: gridLocalX, y: gridLocalY)
        draggingOffset = .zero
        dragAccumulatedOffset = .zero
        dragMouseOffset = .zero
        dragStartPage = currentPage
        dragEdgeStartTime = nil
        isDraggingFromFolder = true

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

        // Start mouse tracking to update drag position
        startMouseTrackingForFolderDrag(cellWidth: cellWidth, cellHeight: cellHeight, geo: geo)

        LauncherSettings.saveGridItems(gridState.stableItems)
    }

    private func startMouseTrackingForFolderDrag(cellWidth: CGFloat, cellHeight: CGFloat, geo: GeometryProxy) {
        // Remove any existing monitor
        if let monitor = mouseTrackingMonitor {
            NSEvent.removeMonitor(monitor)
        }

        mouseTrackingMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [self] event in
            guard isDraggingFromFolder, draggingItem != nil else {
                return event
            }

            if event.type == .leftMouseUp {
                // End dragging
                stopMouseTrackingForFolderDrag()
                finishDragging()
                return event
            }

            // Update position based on mouse location
            let mouseLocation = NSEvent.mouseLocation
            if let screen = NSScreen.main {
                let mouseInViewX = mouseLocation.x
                let mouseInViewY = screen.frame.height - mouseLocation.y

                // Update dragging offset relative to start position
                draggingOffset = CGSize(
                    width: mouseInViewX - dragStartPosition.x,
                    height: mouseInViewY - dragStartPosition.y
                )

                // Calculate screen position for hit testing
                let screenX = mouseInViewX
                let screenY = mouseInViewY

                updateDragPosition(
                    localX: screenX,
                    localY: screenY,
                    cellWidth: cellWidth,
                    cellHeight: cellHeight
                )
            }

            return event
        }
    }

    private func stopMouseTrackingForFolderDrag() {
        if let monitor = mouseTrackingMonitor {
            NSEvent.removeMonitor(monitor)
            mouseTrackingMonitor = nil
        }
        isDraggingFromFolder = false
    }

    private func updateDragPosition(localX: CGFloat, localY: CGFloat, cellWidth: CGFloat, cellHeight: CGFloat) {
        guard let currentIndex = dragCurrentIndex, let dragging = draggingItem else { return }

        // Check for edge drag to change page using local coordinates within the view
        // localX is already in the coordinate space of the current page view
        let edgeThreshold: CGFloat = 50  // pixels from view edge to trigger page change
        let edgeRepeatDelay: TimeInterval = 2.0  // seconds cooldown between page changes

        let isNearLeftEdge = localX < edgeThreshold && currentPage > 0
        let isNearRightEdge = localX > pageWidth - edgeThreshold && currentPage < totalPages - 1
        let isNearEdge = isNearLeftEdge || isNearRightEdge

        if isNearEdge {
            let now = Date()
            var shouldChangePage = false
            var pageDirection: Int = 0  // -1 for left, +1 for right

            // Simple cooldown logic: check if 2s has passed since last page change
            if let lastChangeTime = dragEdgeStartTime {
                let elapsed = now.timeIntervalSince(lastChangeTime)
                if elapsed >= edgeRepeatDelay {
                    shouldChangePage = true
                    pageDirection = isNearLeftEdge ? -1 : 1
                    print("🔄 Cooldown passed (\(String(format: "%.1f", elapsed))s), will change page: \(pageDirection)")
                }
            } else {
                // First page change during this drag - allow immediately
                shouldChangePage = true
                pageDirection = isNearLeftEdge ? -1 : 1
                print("🔄 First edge touch, will change page: \(pageDirection)")
            }

            if shouldChangePage && pageDirection != 0 {
                let newPage = currentPage + pageDirection

                // Record this page change time for cooldown
                dragEdgeStartTime = now

                // Update dragAccumulatedOffset to compensate for page change
                // This keeps the visual icon position consistent with cursor
                dragAccumulatedOffset.width -= CGFloat(pageDirection) * pageWidth

                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage = newPage
                }
                print("🔄 Page changed to \(newPage)")
            }
        }
        // Note: We never reset dragEdgeStartTime until drag ends
        // This ensures 2s cooldown regardless of cursor position

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

        // Use local coordinates for hit testing (relative to current page)
        dragStateMachine.updateDrag(
            position: CGPoint(x: localX, y: localY),
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
        dragEdgeStartTime = nil
        dragStartPage = 0
        dragStateMachine.reset()

        // Commit and save
        gridState.commitPreview()
        LauncherSettings.saveGridItems(gridState.stableItems)
    }

    private func finishDragging() {
        // Ask state machine if we should merge (do this FIRST to determine intent)
        let (shouldMerge, targetId, _) = dragStateMachine.endDrag()

        // If merge state reached, clear drag-into-folder state
        // Merge takes precedence over dropping into folder
        if shouldMerge && targetId != nil {
            dragIntoFolderTargetId = nil
            dragIntoFolderTargetIndex = nil
        }

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
            let insertAt = min(targetInsertIndex, folder.slots.count)
            folder.slots.insert(contentsOf: appsToAdd.map { .app($0) }, at: insertAt)

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
            dragEdgeStartTime = nil
            dragIntoFolderTargetId = nil
            dragIntoFolderTargetIndex = nil
            dragStateMachine.reset()
            return
        }

        // Use the shouldMerge/targetId from endDrag() called earlier
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
        dragEdgeStartTime = nil
        dragStartPage = 0
        dragIntoFolderTargetId = nil
        dragIntoFolderTargetIndex = nil
        stopMouseTrackingForFolderDrag()
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

    // Drag-to-reorder state for folder items (using GridState like launcher)
    @StateObject private var folderGridState = GridState()
    @State private var draggingItem: LauncherItem?
    @State private var draggingOffset: CGSize = .zero
    @State private var dragStartPosition: CGPoint = .zero
    @State private var dragCurrentIndex: Int?  // Index in stable (never changes during drag)
    @State private var folderDragAccumulatedOffset: CGFloat = 0  // Compensate for page changes
    @State private var folderDragMouseOffset: CGSize = .zero  // Mouse click position relative to icon center
    @State private var folderDragStartPage: Int = 0  // Page where drag started

    // Track external drag position inside folder
    @State private var externalDragTargetIndex: Int?

    // Edge drag state for page change within folder
    @State private var folderEdgeStartTime: Date? = nil  // Cooldown timer for page changes

    // Debug: mouse position tracking
    @State private var debugMousePosition: CGPoint = .zero
    @State private var debugMouseMonitor: Any?

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

    /// Items to display (from folderGridState, which handles preview/stable)
    private var folderItems: [LauncherItem] {
        folderGridState.items.isEmpty ? folder.slots : folderGridState.items
    }

    private var totalPages: Int {
        max(1, Int(ceil(Double(folderItems.count) / Double(appsPerPage))))
    }

    /// Get items for page (uses folderGridState.items which handles preview during drag)
    private func itemsForPage(_ page: Int) -> [(position: Int, item: LauncherItem)] {
        let start = page * appsPerPage
        let end = min(start + appsPerPage, folderItems.count)
        guard start < folderItems.count else { return [] }

        var result: [(position: Int, item: LauncherItem)] = []
        for (offset, index) in (start..<end).enumerated() {
            let item = folderItems[index]
            if !item.isEmpty {
                result.append((position: offset, item: item))
            }
        }

        // IMPORTANT: If we're dragging an item and this is the page where drag started,
        // ensure the dragging item is included (even if preview moved it elsewhere).
        // This keeps the DragGesture alive.
        if let dragging = draggingItem, page == folderDragStartPage {
            let alreadyIncluded = result.contains { $0.item.id == dragging.id }
            if !alreadyIncluded {
                // Add it at position 0 (actual position doesn't matter since it's invisible)
                result.append((position: 0, item: dragging))
            }
        }

        return result
    }

    private func finishFolderDragging() {
        // Check if we have changes to commit
        if folderGridState.previewHasChanges {
            // Commit the preview to stable
            folderGridState.commitPreview()

            // Update folder with new slots
            // NOTE: Don't compact() here - folder now supports empty slots like launcher
            var updated = folder
            updated.slots = folderGridState.stableItems
            onFolderUpdate(updated)
            print("✅ Folder drag committed, slots: \(updated.slots.map { $0.name })")
        } else {
            // No changes, cancel preview (revert to stable)
            folderGridState.cancelPreview()
            print("↩️ Folder drag cancelled (no changes)")
        }

        // Clear drag state
        draggingItem = nil
        draggingOffset = .zero
        dragStartPosition = .zero
        dragCurrentIndex = nil
        folderEdgeStartTime = nil
        folderDragAccumulatedOffset = 0
        folderDragMouseOffset = .zero
        folderDragStartPage = 0
    }

    /// Handle folder drag position update (edge detection, outside detection, apply operation)
    private func updateFolderDragPosition(
        dragX: CGFloat,
        dragY: CGFloat,
        cellWidth: CGFloat,
        cellHeight: CGFloat,
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        folderPadding: CGFloat,
        titleHeight: CGFloat,
        geo: GeometryProxy,
        app: AppItem
    ) {
        guard let sourceIndex = dragCurrentIndex, draggingItem != nil else { return }

        // Edge detection for page change within folder
        let edgeWidth = iconSize / 2
        let folderLeftEdge = -folderPadding / 2
        let folderRightEdge = contentWidth + folderPadding / 2

        let leftZoneStart = folderLeftEdge - edgeWidth
        let leftZoneEnd = folderLeftEdge
        let rightZoneStart = folderRightEdge
        let rightZoneEnd = folderRightEdge + edgeWidth

        // dragX is already the screen position (compensated for page changes in caller)
        // No need to add folderDragAccumulatedOffset here
        let isNearLeftEdge = dragX >= leftZoneStart && dragX <= leftZoneEnd && currentPage > 0
        let isNearRightEdge = dragX >= rightZoneStart && dragX <= rightZoneEnd && currentPage < totalPages - 1
        let isNearEdge = isNearLeftEdge || isNearRightEdge

        if isNearEdge {
            let now = Date()
            let edgeRepeatDelay: TimeInterval = 2.0
            var shouldChangePage = false
            var pageDirection: Int = 0

            // Simple cooldown logic: check if 2s has passed since last page change
            if let lastChangeTime = folderEdgeStartTime {
                let elapsed = now.timeIntervalSince(lastChangeTime)
                if elapsed >= edgeRepeatDelay {
                    shouldChangePage = true
                    pageDirection = isNearLeftEdge ? -1 : 1
                    print("📁 Folder: Cooldown passed (\(String(format: "%.1f", elapsed))s), will change page: \(pageDirection)")
                }
            } else {
                // First page change during this drag - allow immediately
                shouldChangePage = true
                pageDirection = isNearLeftEdge ? -1 : 1
                print("📁 Folder: First edge touch, will change page: \(pageDirection)")
            }

            if shouldChangePage && pageDirection != 0 {
                // Record this page change time for cooldown
                folderEdgeStartTime = now

                // Update accumulated offset to compensate for page change
                folderDragAccumulatedOffset -= CGFloat(pageDirection) * contentWidth

                withAnimation(.easeInOut(duration: 0.3)) {
                    currentPage += pageDirection
                }
                print("📁 Folder: Page changed to \(currentPage)")
            }
        }
        // Note: We never reset folderEdgeStartTime until drag ends
        // This ensures 2s cooldown regardless of cursor position

        // Check if dragged outside folder bounds
        let isOutside = dragX < leftZoneStart ||
                       dragX > rightZoneEnd ||
                       dragY < -folderPadding / 2 - titleHeight ||
                       dragY > contentHeight + folderPadding / 2

        if isOutside {
            // Get mouse position for handoff
            let mouseLocation = NSEvent.mouseLocation
            if let screen = NSScreen.main {
                let mouseInViewX = mouseLocation.x
                let mouseInViewY = screen.frame.height - mouseLocation.y

                print("📤 Dragging out of folder: \(app.name)")

                // Clear drag state FIRST to prevent re-entry
                let draggedApp = app
                draggingItem = nil
                draggingOffset = .zero
                dragCurrentIndex = nil
                folderGridState.cancelPreview()

                // Use actual mouse position for handoff
                onDragOutOfFolder(draggedApp, CGPoint(x: mouseInViewX, y: mouseInViewY))
            }
            return
        }

        // Use calculateHitPosition and determineOperation (same as launcher)
        let layout = GridLayoutParams(
            columnsCount: folderColumns,
            rowsCount: folderRows,
            appsPerPage: appsPerPage,
            cellWidth: cellWidth,
            cellHeight: cellHeight,
            iconSize: iconSize,
            horizontalPadding: 0,  // Folder content starts at (0, 0)
            topPadding: 0
        )

        let hitResult = calculateHitPosition(
            position: CGPoint(x: dragX, y: dragY),
            currentPage: currentPage,
            layout: layout
        )

        var operation = determineOperation(
            hitResult: hitResult,
            items: folderGridState.items,
            draggingItemId: draggingItem?.id ?? UUID(),
            layout: layout
        )

        // Folder doesn't support merge (folders can't contain folders)
        if operation == .merge {
            operation = .none
        }

        // Apply the operation to preview
        if operation != .none, let cell = hitResult.cell {
            let targetIndex = cell.toIndex(columnsCount: folderColumns, appsPerPage: appsPerPage)
            print("📁 Folder drag: operation=\(operation), sourceIndex=\(sourceIndex), targetIndex=\(targetIndex), page=\(currentPage)")

            let beforeItems = folderGridState.items
            folderGridState.applyOperation(
                operation: operation,
                targetCell: hitResult.cell,
                sourceIndex: sourceIndex,
                layout: layout
            )

            logFolderItems(label: "Before", items: beforeItems, cellWidth: cellWidth, cellHeight: cellHeight)
            logFolderItems(label: "After", items: folderGridState.items, cellWidth: cellWidth, cellHeight: cellHeight)
        }
    }

    /// Log folder layout as 2D grid (all pages) with UI parameters
    private func logFolderLayout(label: String, contentWidth: CGFloat, contentHeight: CGFloat, cellWidth: CGFloat, cellHeight: CGFloat) {
        let displayItems = folderGridState.items.isEmpty ? folder.slots : folderGridState.items
        logFolderItems(label: label, items: displayItems, cellWidth: cellWidth, cellHeight: cellHeight)
    }

    /// Log folder items as 2D grid (all pages)
    private func logFolderItems(label: String, items: [LauncherItem], cellWidth: CGFloat, cellHeight: CGFloat) {
        let itemsPerPage = folderRows * folderColumns
        let pages = max(1, Int(ceil(Double(items.count) / Double(itemsPerPage))))

        var lines: [String] = []
        lines.append("📁 [\(label)] Folder '\(folder.name)' (\(items.count) items)")

        for page in 0..<pages {
            if pages > 1 {
                lines.append("  --- Page \(page) ---")
            }
            let pageStart = page * itemsPerPage

            for row in 0..<folderRows {
                var rowItems: [String] = []
                for col in 0..<folderColumns {
                    let index = pageStart + row * folderColumns + col
                    if index < items.count {
                        let item = items[index]
                        let isDragging = draggingItem?.id == item.id
                        let name = String(item.name.prefix(6))
                        let posInfo = item.isEmpty ? "·" : name
                        rowItems.append(isDragging ? "[\(posInfo)]" : posInfo)
                    } else {
                        rowItems.append("·")
                    }
                }
                lines.append("  " + rowItems.joined(separator: " | "))
            }
        }

        print(lines.joined(separator: "\n"))
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

        // Cell size within folder content area
        let cellWidth = contentWidth / CGFloat(folderColumns)
        let cellHeight = contentHeight / CGFloat(folderRows)

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

                    // Paginated apps grid - wrapped in a ZStack so dragging overlay is outside page offset
                    ZStack {
                        // Page content (scrolls with page changes)
                        HStack(spacing: 0) {
                            ForEach(0..<totalPages, id: \.self) { page in
                            // Grid for each page - use ZStack with position like launcher
                            ZStack {
                                let pageItems = itemsForPage(page)
                                ForEach(pageItems, id: \.item.id) { itemData in
                                    let item = itemData.item
                                    let position = itemData.position
                                    let row = position / folderColumns
                                    let col = position % folderColumns
                                    let x = cellWidth * (CGFloat(col) + 0.5)
                                    let y = cellHeight * (CGFloat(row) + 0.5)
                                    let isDragging = draggingItem?.id == item.id
                                    let globalIndex = folderItems.firstIndex(where: { $0.id == item.id }) ?? (page * appsPerPage + position)

                                    // Get app from item (folder slots should only contain apps or empty)
                                    if case .app(let app) = item {
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
                                                updated.slots.removeAll { $0.id == item.id }
                                                updated.compact()
                                                onFolderUpdate(updated)
                                                if updated.apps.isEmpty {
                                                    onClose()
                                                }
                                            }
                                        )
                                        // Hide item visually when dragging (it's rendered in overlay)
                                        .opacity(isDragging ? 0 : 1.0)
                                        // Animate position changes for non-dragging items
                                        .animation(isDragging ? nil : .easeInOut(duration: 0.2), value: position)
                                        .position(x: x, y: y)
                                        .highPriorityGesture(
                                                DragGesture(minimumDistance: 15)
                                                    .onChanged { drag in
                                                        if draggingItem == nil {
                                                            draggingItem = item
                                                            dragCurrentIndex = globalIndex
                                                            dragStartPosition = CGPoint(x: x, y: y)
                                                            folderDragAccumulatedOffset = 0
                                                            folderDragStartPage = currentPage  // Remember which page we started on
                                                            folderEdgeStartTime = nil  // Reset cooldown for new drag
                                                            // Record mouse click offset relative to icon center
                                                            folderDragMouseOffset = CGSize(
                                                                width: drag.startLocation.x - x,
                                                                height: drag.startLocation.y - y
                                                            )
                                                            // Initialize folderGridState with current folder slots
                                                            folderGridState.setStable(folder.slots)
                                                            folderGridState.startPreview()
                                                            logFolderLayout(label: "Drag Start - \(app.name)", contentWidth: contentWidth, contentHeight: contentHeight, cellWidth: cellWidth, cellHeight: cellHeight)
                                                        }

                                                        if draggingItem != nil {
                                                            // Apply accumulated offset and mouse offset to keep icon attached to cursor
                                                            // folderDragAccumulatedOffset compensates for page changes
                                                            draggingOffset = CGSize(
                                                                width: drag.translation.width + folderDragAccumulatedOffset + folderDragMouseOffset.width,
                                                                height: drag.translation.height + folderDragMouseOffset.height
                                                            )

                                                            // Calculate screen position for hit testing
                                                            // This needs to compensate for page changes to map to correct cell
                                                            let pageOffset = CGFloat(currentPage - folderDragStartPage) * contentWidth
                                                            let screenX = dragStartPosition.x + drag.translation.width + folderDragMouseOffset.width - pageOffset
                                                            let screenY = dragStartPosition.y + drag.translation.height + folderDragMouseOffset.height

                                                            // Update drag position (handles edge detection, outside detection, and operation)
                                                            updateFolderDragPosition(
                                                                dragX: screenX,
                                                                dragY: screenY,
                                                                cellWidth: cellWidth,
                                                                cellHeight: cellHeight,
                                                                contentWidth: contentWidth,
                                                                contentHeight: contentHeight,
                                                                folderPadding: folderPadding,
                                                                titleHeight: titleHeight,
                                                                geo: geo,
                                                                app: app
                                                            )
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        if draggingItem != nil {
                                                            finishFolderDragging()
                                                        }
                                                    }
                                        )
                                    }
                                }
                            }
                            .frame(width: contentWidth, height: contentHeight)
                        }
                    }
                    .offset(x: -CGFloat(currentPage) * contentWidth + dragOffset)
                    .animation(.easeInOut(duration: 0.3), value: currentPage)

                        // Dragging item overlay - rendered outside the HStack so it's not affected by page offset
                        if let dragging = draggingItem, case .app(let app) = dragging {
                            let displayX = dragStartPosition.x + draggingOffset.width
                            let displayY = dragStartPosition.y + draggingOffset.height

                            FolderAppItemView(
                                app: app,
                                iconSize: iconSize,
                                onTap: {},
                                onRemove: {}
                            )
                            .scaleEffect(1.1)
                            .opacity(0.9)
                            .position(x: displayX, y: displayY)
                            .zIndex(100)
                            .allowsHitTesting(false)
                        }
                    }  // ZStack
                    .frame(width: contentWidth, height: contentHeight, alignment: .leading)
                    .contentShape(Rectangle())  // Enable hit testing on empty areas for drag gesture
                    .clipped()
                    .gesture(
                        DragGesture(minimumDistance: 15)
                            .onChanged { value in
                                // Only handle page swipe if not dragging an item
                                if draggingItem == nil {
                                    dragOffset = value.translation.width
                                    // Rubber-band effect at edges
                                    if currentPage == 0 && dragOffset > 0 {
                                        dragOffset = min(dragOffset, 50)
                                    } else if currentPage == totalPages - 1 && dragOffset < 0 {
                                        dragOffset = max(dragOffset, -50)
                                    }
                                }
                            }
                            .onEnded { value in
                                // Only handle page swipe if not dragging an item
                                if draggingItem == nil {
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
                .background(folderBackground(folderWidth: folderWidth, folderHeight: folderHeight))
                .overlay(folderDebugOverlay(folderWidth: folderWidth, folderHeight: folderHeight, geoSize: geo.size))
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                // Folder content animation (expand/collapse)
                .transition(.opacity.combined(with: .scale(scale: 0.8)))
            }
        }
        // No transition on the container - the dimmed background appears instantly
        .onAppear {
            startFolderScrollMonitor()
            startDebugMouseMonitor()
            logFolderLayout(label: "Open", contentWidth: contentWidth, contentHeight: contentHeight, cellWidth: cellWidth, cellHeight: cellHeight)
        }
        .onDisappear {
            stopFolderScrollMonitor()
            stopDebugMouseMonitor()
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

            // Cell size within folder
            let cellWidth = contentWidth / CGFloat(folderColumns)
            let cellHeight = contentHeight / CGFloat(folderRows)

            // Calculate folder content bounds
            let folderLeft = folderCenterX - contentWidth / 2
            let folderTop = folderCenterY - (contentHeight + titleHeight + folderPadding) / 2 + titleHeight + folderPadding / 2 + 12

            // Convert drag position to folder local coordinates
            let localX = dragX - folderLeft
            let localY = dragY - folderTop

            // Calculate target cell
            let targetCol = Int(floor(localX / cellWidth))
            let targetRow = Int(floor(localY / cellHeight))

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

    private func startDebugMouseMonitor() {
        debugMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [self] event in
            if let screen = NSScreen.main {
                let mouseLocation = NSEvent.mouseLocation
                let mouseInViewX = mouseLocation.x
                let mouseInViewY = screen.frame.height - mouseLocation.y
                debugMousePosition = CGPoint(x: mouseInViewX, y: mouseInViewY)
            }
            return event
        }
    }

    private func stopDebugMouseMonitor() {
        if let monitor = debugMouseMonitor {
            NSEvent.removeMonitor(monitor)
            debugMouseMonitor = nil
        }
    }

    // MARK: - Debug Helper Views

    @ViewBuilder
    private func folderBackground(folderWidth: CGFloat, folderHeight: CGFloat) -> some View {
        ZStack {
            // Main folder background with blur
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.clear)
                .background(
                    VisualEffectView()
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                )

            // DEBUG: Folder visual area (blue) - entire folder bounds
            RoundedRectangle(cornerRadius: 20)
                .fill(Color.blue.opacity(0.3))
        }
    }

    @ViewBuilder
    private func folderDebugOverlay(folderWidth: CGFloat, folderHeight: CGFloat, geoSize: CGSize) -> some View {
        ZStack {
            // DEBUG: Left edge zone (red) - OUTSIDE folder, triggers page change to previous
            Rectangle()
                .fill(Color.red.opacity(0.5))
                .frame(width: iconSize / 2, height: folderHeight)
                .position(x: -iconSize / 4, y: folderHeight / 2)

            // DEBUG: Right edge zone (red) - OUTSIDE folder, triggers page change to next
            Rectangle()
                .fill(Color.red.opacity(0.5))
                .frame(width: iconSize / 2, height: folderHeight)
                .position(x: folderWidth + iconSize / 4, y: folderHeight / 2)

            // DEBUG: Mouse position display
            Text("(\(Int(debugMousePosition.x)), \(Int(debugMousePosition.y)))")
                .font(.caption)
                .foregroundColor(.white)
                .padding(4)
                .background(Color.black.opacity(0.7))
                .cornerRadius(4)
                .position(x: debugMousePosition.x - geoSize.width / 2 + folderWidth / 2,
                          y: debugMousePosition.y - geoSize.height / 2 + folderHeight / 2 - 20)
        }
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

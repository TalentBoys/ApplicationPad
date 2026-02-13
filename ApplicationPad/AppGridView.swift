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
    @State private var orderedApps: [AppItem] = []  // Display order, updated during drag
    @State private var keyMonitor = KeyEventMonitor()
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var scrollMonitor: Any?
    @State private var pageWidth: CGFloat = 0
    @State private var scrollEndTimer: Timer?
    @FocusState private var isSearchFocused: Bool

    // Drag-to-reorder state
    @State private var draggingApp: AppItem?
    @State private var draggingOffset: CGSize = .zero
    @State private var dragCurrentIndex: Int?
    @State private var dragStartPosition: CGPoint = .zero  // Initial position when drag started
    @State private var isDraggingPage: Bool = false  // Track if we're dragging the page

    var columnsCount: Int { LauncherSettings.columnsCount }
    var rowsCount: Int { LauncherSettings.rowsCount }
    var appsPerPage: Int { LauncherSettings.appsPerPage }
    var iconSize: CGFloat { LauncherSettings.iconSize }
    var horizontalPadding: CGFloat { LauncherSettings.horizontalPadding }
    var topPadding: CGFloat { LauncherSettings.topPadding }
    var bottomPadding: CGFloat { LauncherSettings.bottomPadding }

    var filteredApps: [AppItem] {
        let key = searchText.lowercased()
        if key.isEmpty {
            return orderedApps.isEmpty ? LauncherSettings.applyCustomOrder(to: apps) : orderedApps
        }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(key)
            || $0.pinyinName.contains(key)
            || $0.pinyinInitials.contains(key)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func refreshOrderedApps() {
        orderedApps = LauncherSettings.applyCustomOrder(to: apps)
    }

    var totalPages: Int {
        max(1, Int(ceil(Double(filteredApps.count) / Double(appsPerPage))))
    }

    var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 20), count: columnsCount)
    }

    func appsForPage(_ page: Int) -> [AppItem] {
        let start = page * appsPerPage
        let end = min(start + appsPerPage, filteredApps.count)
        guard start < filteredApps.count else { return [] }
        return Array(filteredApps[start..<end])
    }

    var body: some View {
        GeometryReader { geometry in
            let screenWidth = geometry.size.width
            let screenHeight = geometry.size.height
            let notchHeight: CGFloat = 50
            let searchHeight: CGFloat = 60
            let pageIndicatorHeight: CGFloat = totalPages > 1 ? 50 : 0
            let availableWidth = screenWidth - horizontalPadding * 2
            let availableHeight = screenHeight - notchHeight - searchHeight - pageIndicatorHeight - topPadding - bottomPadding
            let cellWidth = availableWidth / CGFloat(columnsCount)
            let cellHeight = availableHeight / CGFloat(rowsCount)

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
                                    let pageApps = appsForPage(page)
                                    ZStack {
                                        ForEach(Array(pageApps.enumerated()), id: \.element.url) { index, app in
                                            let globalIndex = page * appsPerPage + index
                                            let row = index / columnsCount
                                            let col = index % columnsCount
                                            let x = horizontalPadding + cellWidth * (CGFloat(col) + 0.5)
                                            let y = topPadding + cellHeight * (CGFloat(row) + 0.5)
                                            let isDragging = draggingApp?.url == app.url

                                            // For dragging item: use start position + offset
                                            // For other items: use grid position with animation
                                            let displayX = isDragging ? dragStartPosition.x : x
                                            let displayY = isDragging ? dragStartPosition.y : y

                                            AppItemView(app: app, iconSize: iconSize) {
                                                apps = AppScanner.scan()
                                                refreshOrderedApps()
                                            }
                                            .position(x: displayX, y: displayY)
                                            .offset(isDragging ? draggingOffset : .zero)
                                            .scaleEffect(isDragging ? 1.1 : 1.0)
                                            .zIndex(isDragging ? 100 : 0)
                                            .opacity(isDragging ? 0.9 : 1.0)
                                            .animation(isDragging ? nil : .easeInOut(duration: 0.2), value: orderedApps.map { $0.url })
                                            .highPriorityGesture(
                                                DragGesture(minimumDistance: 15)
                                                    .onChanged { drag in
                                                        // Start dragging on first trigger (distance exceeded)
                                                        if draggingApp == nil && searchText.isEmpty {
                                                            draggingApp = app
                                                            dragCurrentIndex = globalIndex
                                                            dragStartPosition = CGPoint(x: x, y: y)
                                                        }

                                                        if draggingApp?.url == app.url {
                                                            draggingOffset = drag.translation

                                                            // Calculate target position based on start position
                                                            let dragX = dragStartPosition.x + drag.translation.width
                                                            let dragY = dragStartPosition.y + drag.translation.height

                                                            updateDragPosition(
                                                                dragX: dragX,
                                                                dragY: dragY,
                                                                cellWidth: cellWidth,
                                                                cellHeight: cellHeight
                                                            )
                                                        }
                                                    }
                                                    .onEnded { _ in
                                                        if draggingApp?.url == app.url {
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
                        .contentShape(Rectangle())  // Make entire area respond to gestures
                        .onTapGesture {
                            // Tap on empty area to close
                            print("[TAP] Grid area tapped, isDraggingPage=\(isDraggingPage), draggingApp=\(draggingApp?.name ?? "nil")")
                            if !isDraggingPage && draggingApp == nil {
                                print("[TAP] Closing launcher")
                                closeLauncher()
                            }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 15)
                                .onChanged { value in
                                    print("[PAGE_DRAG] onChanged, draggingApp=\(draggingApp?.name ?? "nil")")
                                    // Only handle page swipe if not dragging an app
                                    if draggingApp == nil {
                                        isDraggingPage = true
                                        print("[PAGE_DRAG] Set isDraggingPage=true")
                                        dragOffset = value.translation.width

                                        // Apply boundary resistance
                                        if currentPage == 0 && dragOffset > 0 {
                                            dragOffset = min(dragOffset, 100)
                                        } else if currentPage == totalPages - 1 && dragOffset < 0 {
                                            dragOffset = max(dragOffset, -100)
                                        }
                                    }
                                }
                                .onEnded { value in
                                    print("[PAGE_DRAG] onEnded, isDraggingPage=\(isDraggingPage)")
                                    if draggingApp == nil {
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
                                    print("[PAGE_DRAG] Reset isDraggingPage=false")
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
            }
        }
        .onAppear {
            refreshOrderedApps()
            focusSearchField()
            keyMonitor.startEscListener {
                closeLauncher()
            }
        }
        .onDisappear {
            keyMonitor.stop()
            searchText = ""
            currentPage = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            focusSearchField()
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
    }

    private func updateDragPosition(dragX: CGFloat, dragY: CGFloat, cellWidth: CGFloat, cellHeight: CGFloat) {
        guard let currentIndex = dragCurrentIndex, draggingApp != nil else { return }

        // Calculate target cell
        let col = Int((dragX - horizontalPadding) / cellWidth)
        let row = Int((dragY - topPadding) / cellHeight)

        // Validate bounds
        guard col >= 0, col < columnsCount, row >= 0, row < rowsCount else { return }

        let targetIndexInPage = row * columnsCount + col
        let targetIndex = currentPage * appsPerPage + targetIndexInPage

        // Validate target index and check if changed
        guard targetIndex >= 0, targetIndex < orderedApps.count, targetIndex != currentIndex else { return }

        // Move the app in the array
        withAnimation(.easeInOut(duration: 0.15)) {
            let app = orderedApps.remove(at: currentIndex)
            orderedApps.insert(app, at: targetIndex)
            dragCurrentIndex = targetIndex
        }
    }

    private func finishDragging() {
        // Save the final order
        if !orderedApps.isEmpty {
            LauncherSettings.saveAppOrder(orderedApps)
        }

        withAnimation(.easeOut(duration: 0.2)) {
            draggingApp = nil
            draggingOffset = .zero
            dragCurrentIndex = nil
            dragStartPosition = .zero
        }
    }

    private func startScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Ignore momentum (inertia) phase - only respond to actual user scrolling
            if event.momentumPhase != [] {
                return event
            }

            let invert: CGFloat = LauncherSettings.invertScroll ? -1 : 1
            let sensitivity = LauncherSettings.scrollSensitivity

            let deltaX = event.scrollingDeltaX * invert * sensitivity
            let deltaY = event.scrollingDeltaY * invert * sensitivity

            // Combine horizontal and vertical: left/up = previous page, right/down = next page
            let delta = deltaX - deltaY

            // Skip if no meaningful delta
            guard abs(delta) > 0.1 else { return event }

            // Update drag offset for visual feedback
            dragOffset += delta

            // Limit drag offset to one page width
            let maxOffset = pageWidth > 0 ? pageWidth : 1000
            dragOffset = max(-maxOffset, min(maxOffset, dragOffset))

            // Clamp drag offset at boundaries with resistance
            if currentPage == 0 && dragOffset > 0 {
                dragOffset = min(dragOffset, 100)
            } else if currentPage == totalPages - 1 && dragOffset < 0 {
                dragOffset = max(dragOffset, -100)
            }

            // Reset timer for detecting scroll end
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

struct AppItemView: View {
    let app: AppItem
    let iconSize: CGFloat
    var onLaunch: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        VStack {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: iconSize, height: iconSize)
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovered)

            Text(app.name)
                .font(iconSize > 64 ? .callout : .caption)
                .foregroundColor(.primary)
                .lineLimit(1)
        }
        .padding(8)
        .background(isHovered ? Color.white.opacity(0.2) : Color.clear)
        .cornerRadius(8)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            app.markUsed()
            NSWorkspace.shared.open(app.url)
            onLaunch()
            LauncherPanel.shared.close()
        }
    }
}

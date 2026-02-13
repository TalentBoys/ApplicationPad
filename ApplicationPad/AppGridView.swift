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
    @State private var keyMonitor = KeyEventMonitor()
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    @State private var scrollMonitor: Any?
    @State private var pageWidth: CGFloat = 0
    @State private var scrollEndTimer: Timer?
    @FocusState private var isSearchFocused: Bool

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
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(key)
            || $0.pinyinName.contains(key)
            || $0.pinyinInitials.contains(key)
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
                // Background tap to close
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeLauncher()
                    }

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
                        HStack(spacing: 0) {
                            ForEach(0..<totalPages, id: \.self) { page in
                                let pageApps = appsForPage(page)
                                ZStack {
                                    ForEach(Array(pageApps.enumerated()), id: \.element.id) { index, app in
                                        let row = index / columnsCount
                                        let col = index % columnsCount
                                        let x = horizontalPadding + cellWidth * (CGFloat(col) + 0.5)
                                        let y = topPadding + cellHeight * (CGFloat(row) + 0.5)

                                        AppItemView(app: app, iconSize: iconSize) {
                                            apps = AppScanner.scan()
                                        }
                                        .position(x: x, y: y)
                                    }
                                }
                                .frame(width: geo.size.width, height: geo.size.height)
                            }
                        }
                        .offset(x: -CGFloat(currentPage) * geo.size.width + dragOffset)
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onChanged { value in
                                    dragOffset = value.translation.width
                                }
                                .onEnded { value in
                                    let threshold = geo.size.width * 0.3

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

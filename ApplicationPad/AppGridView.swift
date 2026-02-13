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
    @FocusState private var isSearchFocused: Bool

    var columnsCount: Int { LauncherSettings.columnsCount }
    var rowsCount: Int { LauncherSettings.rowsCount }
    var appsPerPage: Int { LauncherSettings.appsPerPage }
    var iconSize: CGFloat { LauncherSettings.iconSize }

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
            let searchHeight: CGFloat = 60
            let pageIndicatorHeight: CGFloat = totalPages > 1 ? 50 : 0
            let availableHeight = screenHeight - searchHeight - pageIndicatorHeight
            let cellWidth = screenWidth / CGFloat(columnsCount)
            let cellHeight = availableHeight / CGFloat(rowsCount)

            ZStack {
                // Background tap to close
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        closeLauncher()
                    }

                VStack(spacing: 0) {
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
                                        let x = cellWidth * (CGFloat(col) + 0.5)
                                        let y = cellHeight * (CGFloat(row) + 0.5)

                                        AppItemView(app: app, iconSize: iconSize) {
                                            apps = AppScanner.scan()
                                        }
                                        .position(x: x, y: y)
                                    }
                                }
                                .frame(width: geo.size.width, height: geo.size.height)
                            }
                        }
                        .offset(x: -CGFloat(currentPage) * geo.size.width)
                        .animation(.easeInOut(duration: 0.3), value: currentPage)
                        .gesture(
                            DragGesture()
                                .onEnded { value in
                                    let threshold: CGFloat = 50
                                    if value.translation.width < -threshold && currentPage < totalPages - 1 {
                                        currentPage += 1
                                    } else if value.translation.width > threshold && currentPage > 0 {
                                        currentPage -= 1
                                    }
                                }
                        )
                    }
                    .frame(height: availableHeight)

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
                .foregroundColor(.white)
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

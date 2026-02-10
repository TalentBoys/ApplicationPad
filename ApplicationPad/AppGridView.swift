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
    @FocusState private var isSearchFocused: Bool

    var columns: [GridItem] {
        let count = LauncherSettings.columnsCount
        return Array(repeating: GridItem(.flexible(), spacing: 20), count: count)
    }

    var iconSize: CGFloat {
        LauncherSettings.iconSize
    }

    var recentApps: [AppItem] {
        let key = searchText.lowercased()
        let recent = apps.filter { $0.lastUsed != .distantPast }
            .sorted { $0.lastUsed > $1.lastUsed }
            .prefix(LauncherSettings.columnsCount)

        if key.isEmpty {
            return Array(recent)
        }
        return recent.filter {
            $0.name.localizedCaseInsensitiveContains(key)
            || $0.pinyinName.contains(key)
            || $0.pinyinInitials.contains(key)
        }
    }

    var otherApps: [AppItem] {
        let key = searchText.lowercased()
        let recentIDs = Set(recentApps.map { $0.id })
        let others = apps.filter { !recentIDs.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        if key.isEmpty {
            return others
        }
        return others.filter {
            $0.name.localizedCaseInsensitiveContains(key)
            || $0.pinyinName.contains(key)
            || $0.pinyinInitials.contains(key)
        }
    }

    var filteredApps: [AppItem] {
        let key = searchText.lowercased()
        if key.isEmpty {
            return apps
        }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(key)
            || $0.pinyinName.contains(key)
            || $0.pinyinInitials.contains(key)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search box
            TextField("Search applications", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .focused($isSearchFocused)

            ScrollView {
                VStack(spacing: 16) {
                    // Recent apps section
                    if !recentApps.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Recent")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)

                            LazyVGrid(columns: columns, spacing: 20) {
                                ForEach(recentApps) { app in
                                    AppItemView(app: app, iconSize: iconSize) {
                                        apps = AppScanner.scan()
                                    }
                                }
                            }
                        }

                        Divider()
                            .padding(.vertical, 8)
                    }

                    // All other apps
                    VStack(alignment: .leading, spacing: 12) {
                        if !recentApps.isEmpty {
                            Text("All Apps")
                                .font(.headline)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 4)
                        }

                        LazyVGrid(columns: columns, spacing: 20) {
                            ForEach(otherApps) { app in
                                AppItemView(app: app, iconSize: iconSize) {
                                    apps = AppScanner.scan()
                                }
                            }
                        }
                    }
                }
                .padding(20)
                .animation(.interactiveSpring(), value: filteredApps.map { $0.id })
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
                .lineLimit(1)
        }
        .padding(8)
        .background(isHovered ? Color.gray.opacity(0.2) : Color.clear)
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

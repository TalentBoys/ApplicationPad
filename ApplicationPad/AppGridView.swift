//
//  AppGridView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI

struct AppGridView: View {
    let showSettingsHint: Bool
    let isLauncher: Bool

    @State private var searchText = ""
    @State private var apps = AppScanner.scan()
    @State private var keyMonitor = KeyEventMonitor()
    @FocusState private var isSearchFocused: Bool

    init(showSettingsHint: Bool, isLauncher: Bool = false) {
        self.showSettingsHint = showSettingsHint
        self.isLauncher = isLauncher
    }

    let columns = Array(
        repeating: GridItem(.flexible(), spacing: 20),
        count: 6
    )

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
            if showSettingsHint {
                PermissionHintView()
            }

            // Search box
            TextField("Search applications", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .focused($isSearchFocused)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filteredApps) { app in
                        AppItemView(app: app, isLauncher: isLauncher) {
                            // Refresh apps list after launch
                            apps = AppScanner.scan()
                        }
                    }
                }
                .padding(20)
                .animation(.interactiveSpring(), value: filteredApps.map { $0.id })
            }
        }
        .onAppear {
            // Auto focus search box
            isSearchFocused = true

            // Esc to close (only for launcher)
            if isLauncher {
                keyMonitor.startEscListener {
                    NSApp.keyWindow?.orderOut(nil)
                }
            }
        }
        .onDisappear {
            keyMonitor.stop()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)
        ) { notification in
            // Auto hide when losing focus (only for launcher)
            if isLauncher {
                if let window = notification.object as? NSWindow,
                   window.title == "Launcher" {
                    window.orderOut(nil)
                    searchText = "" // Clear search on close
                }
            }
        }
    }
}

struct AppItemView: View {
    let app: AppItem
    let isLauncher: Bool
    var onLaunch: () -> Void = {}

    @State private var isHovered = false

    var body: some View {
        VStack {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 64, height: 64)
                .scaleEffect(isHovered ? 1.1 : 1.0)
                .animation(.easeOut(duration: 0.15), value: isHovered)

            Text(app.name)
                .font(.caption)
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

            // Close launcher after opening app
            if isLauncher {
                NSApp.keyWindow?.orderOut(nil)
            }
        }
    }
}

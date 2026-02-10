//
//  AppGridView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI

struct AppGridView: View {
    let showSettingsHint: Bool

    @State private var searchText = ""
    @State private var apps = AppScanner.scan()

    let columns = Array(
        repeating: GridItem(.flexible(), spacing: 20),
        count: 6
    )

    var filteredApps: [AppItem] {
        if searchText.isEmpty {
            return apps
        }
        return apps.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
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

            ScrollView {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(filteredApps) { app in
                        AppItemView(app: app)
                    }
                }
                .padding(20)
            }
        }
    }
}

struct AppItemView: View {
    let app: AppItem
    @State private var isHovered = false

    var body: some View {
        VStack {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 64, height: 64)

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
            NSWorkspace.shared.open(app.url)
        }
    }
}

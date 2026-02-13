//
//  LauncherSettings.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation

struct LauncherSettings {
    static var iconSize: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "iconSize").nonZero ?? 112) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "iconSize") }
    }

    static var columnsCount: Int {
        get { UserDefaults.standard.integer(forKey: "columnsCount").nonZero ?? 6 }
        set { UserDefaults.standard.set(newValue, forKey: "columnsCount") }
    }

    static var rowsCount: Int {
        get { UserDefaults.standard.integer(forKey: "rowsCount").nonZero ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: "rowsCount") }
    }

    static var horizontalPadding: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "horizontalPadding") as? Double ?? 120) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "horizontalPadding") }
    }

    static var topPadding: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "topPadding") as? Double ?? 30) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "topPadding") }
    }

    static var bottomPadding: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "bottomPadding") as? Double ?? 70) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "bottomPadding") }
    }

    static var invertScroll: Bool {
        get { UserDefaults.standard.bool(forKey: "invertScroll") }
        set { UserDefaults.standard.set(newValue, forKey: "invertScroll") }
    }

    static var scrollSensitivity: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "scrollSensitivity") as? Double ?? 1.0) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "scrollSensitivity") }
    }

    static var appsPerPage: Int {
        columnsCount * rowsCount
    }

    // MARK: - Grid Items Storage (Apps + Folders)

    private static let gridItemsKey = "gridItems"

    // Codable wrapper for LauncherItem
    private struct LauncherItemData: Codable {
        let type: String // "app", "folder", or "empty"
        let appData: AppItem?
        let folderData: FolderItem?
        let emptyId: UUID?

        init(from launcherItem: LauncherItem) {
            switch launcherItem {
            case .app(let app):
                type = "app"
                appData = app
                folderData = nil
                emptyId = nil
            case .folder(let folder):
                type = "folder"
                appData = nil
                folderData = folder
                emptyId = nil
            case .empty(let id):
                type = "empty"
                appData = nil
                folderData = nil
                emptyId = id
            }
        }

        func toLauncherItem() -> LauncherItem? {
            switch type {
            case "app":
                if let app = appData { return .app(app) }
            case "folder":
                if let folder = folderData { return .folder(folder) }
            case "empty":
                if let id = emptyId { return .empty(id) }
            default:
                break
            }
            return nil
        }
    }

    static func saveGridItems(_ items: [LauncherItem]) {
        let data = items.map { LauncherItemData(from: $0) }
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: gridItemsKey)
        }
    }

    static func loadGridItems() -> [LauncherItem]? {
        guard let data = UserDefaults.standard.data(forKey: gridItemsKey),
              let decoded = try? JSONDecoder().decode([LauncherItemData].self, from: data) else {
            return nil
        }
        return decoded.compactMap { $0.toLauncherItem() }
    }

    static func applyCustomOrder(to apps: [AppItem]) -> [LauncherItem] {
        // Try to load saved grid items first
        if let savedItems = loadGridItems() {
            var result: [LauncherItem] = []
            var remainingApps = apps

            for savedItem in savedItems {
                switch savedItem {
                case .app(let savedApp):
                    // Find matching app by URL
                    if let index = remainingApps.firstIndex(where: { $0.url == savedApp.url }) {
                        result.append(.app(remainingApps.remove(at: index)))
                    }
                case .folder(let folder):
                    // Rebuild folder with current app instances
                    var updatedApps: [AppItem] = []
                    for folderApp in folder.apps {
                        if let index = remainingApps.firstIndex(where: { $0.url == folderApp.url }) {
                            updatedApps.append(remainingApps.remove(at: index))
                        }
                    }
                    if !updatedApps.isEmpty {
                        result.append(.folder(FolderItem(id: folder.id, name: folder.name, apps: updatedApps)))
                    }
                case .empty(let id):
                    // Preserve empty slots to maintain page structure
                    result.append(.empty(id))
                }
            }

            // Append any new apps not in saved order
            remainingApps.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for app in remainingApps {
                result.append(.app(app))
            }

            return result
        }

        // No saved items, return apps sorted alphabetically
        let sortedApps = apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return sortedApps.map { .app($0) }
    }

    // Legacy support - keep old methods for compatibility
    static var customAppOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: "customAppOrder") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "customAppOrder") }
    }

    static func saveAppOrder(_ apps: [AppItem]) {
        customAppOrder = apps.map { $0.url.path }
    }
}

extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}

extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}

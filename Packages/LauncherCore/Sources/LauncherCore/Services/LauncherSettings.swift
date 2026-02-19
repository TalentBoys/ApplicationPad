//
//  LauncherSettings.swift
//  LauncherCore
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation

public struct LauncherSettings {
    public static var iconSize: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "iconSize").nonZero ?? 112) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "iconSize") }
    }

    public static var columnsCount: Int {
        get { UserDefaults.standard.integer(forKey: "columnsCount").nonZero ?? 6 }
        set { UserDefaults.standard.set(newValue, forKey: "columnsCount") }
    }

    public static var rowsCount: Int {
        get { UserDefaults.standard.integer(forKey: "rowsCount").nonZero ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: "rowsCount") }
    }

    public static var horizontalPadding: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "horizontalPadding") as? Double ?? 120) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "horizontalPadding") }
    }

    public static var topPadding: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "topPadding") as? Double ?? 30) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "topPadding") }
    }

    public static var bottomPadding: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "bottomPadding") as? Double ?? 70) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "bottomPadding") }
    }

    public static var invertScroll: Bool {
        get { UserDefaults.standard.bool(forKey: "invertScroll") }
        set { UserDefaults.standard.set(newValue, forKey: "invertScroll") }
    }

    public static var scrollSensitivity: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "scrollSensitivity") as? Double ?? 1.0) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "scrollSensitivity") }
    }

    public static var lastPage: Int {
        get { UserDefaults.standard.integer(forKey: "lastPage") }
        set { UserDefaults.standard.set(newValue, forKey: "lastPage") }
    }

    public static var appsPerPage: Int {
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

    public static func saveGridItems(_ items: [LauncherItem]) {
        let data = items.map { LauncherItemData(from: $0) }
        if let encoded = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(encoded, forKey: gridItemsKey)
        }
    }

    public static func loadGridItems() -> [LauncherItem]? {
        guard let data = UserDefaults.standard.data(forKey: gridItemsKey),
              let decoded = try? JSONDecoder().decode([LauncherItemData].self, from: data) else {
            return nil
        }
        let items = decoded.compactMap { $0.toLauncherItem() }
        // Clean up duplicates on load
        return removeDuplicateApps(from: items)
    }

    /// Remove duplicate apps from grid items (keeps first occurrence)
    /// Duplicates can occur due to bugs in drag operations
    private static func removeDuplicateApps(from items: [LauncherItem]) -> [LauncherItem] {
        var seenURLs = Set<URL>()
        var result: [LauncherItem] = []
        var hadDuplicates = false

        for item in items {
            switch item {
            case .app(let app):
                if seenURLs.contains(app.url) {
                    // Skip duplicate
                    print("⚠️ Removing duplicate app: \(app.name)")
                    hadDuplicates = true
                } else {
                    seenURLs.insert(app.url)
                    result.append(item)
                }
            case .folder(let folder):
                // Also dedupe apps inside folders
                var cleanedApps: [AppItem] = []
                for app in folder.apps {
                    if seenURLs.contains(app.url) {
                        print("⚠️ Removing duplicate app from folder '\(folder.name)': \(app.name)")
                        hadDuplicates = true
                    } else {
                        seenURLs.insert(app.url)
                        cleanedApps.append(app)
                    }
                }
                if cleanedApps.isEmpty {
                    // Folder became empty, skip it
                    print("⚠️ Removing empty folder: \(folder.name)")
                    hadDuplicates = true
                } else {
                    var cleanedFolder = folder
                    cleanedFolder.slots = cleanedApps.map { .app($0) }
                    result.append(.folder(cleanedFolder))
                }
            case .empty:
                result.append(item)
            }
        }

        // If duplicates were found, save the cleaned data
        if hadDuplicates {
            print("✅ Cleaned up duplicate apps, saving...")
            saveGridItems(result)
        }

        return result
    }

    public static func applyCustomOrder(to apps: [AppItem]) -> [LauncherItem] {
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

    // Reset grid layout to default (clear all custom order and folders)
    public static func resetGridLayout() {
        UserDefaults.standard.removeObject(forKey: gridItemsKey)
        UserDefaults.standard.removeObject(forKey: "customAppOrder")
        FolderIconCache.shared.clearCache()
        IconCache.shared.clearCache()
    }

    // Legacy support - keep old methods for compatibility
    public static var customAppOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: "customAppOrder") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "customAppOrder") }
    }

    public static func saveAppOrder(_ apps: [AppItem]) {
        customAppOrder = apps.map { $0.url.path }
    }
}

//
//  AppScanner.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation
import AppKit

// MARK: - Icon Cache

final class IconCache {
    static let shared = IconCache()
    private var cache: [URL: NSImage] = [:]
    private let queue = DispatchQueue(label: "IconCache", attributes: .concurrent)

    private init() {}

    func icon(for url: URL) -> NSImage {
        // Try to get from cache first (read)
        var cachedIcon: NSImage?
        queue.sync {
            cachedIcon = cache[url]
        }

        if let icon = cachedIcon {
            return icon
        }

        // Load icon
        let icon = NSWorkspace.shared.icon(forFile: url.path)

        // Store in cache (write)
        queue.async(flags: .barrier) { [weak self] in
            self?.cache[url] = icon
        }

        return icon
    }

    func clearCache() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }
}

struct AppItem: Identifiable, Equatable, Codable {
    let id: UUID
    let name: String
    let url: URL
    let pinyinName: String      // 完整拼音: wangyiyoudaocidian
    let pinyinInitials: String  // 首字母: wyydcd

    var icon: NSImage {
        IconCache.shared.icon(for: url)
    }

    var lastUsed: Date {
        UserDefaults.standard.object(forKey: url.path) as? Date ?? .distantPast
    }

    func markUsed() {
        UserDefaults.standard.set(Date(), forKey: url.path)
    }

    static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.url == rhs.url
    }

    init(id: UUID = UUID(), name: String, url: URL, pinyinName: String, pinyinInitials: String) {
        self.id = id
        self.name = name
        self.url = url
        self.pinyinName = pinyinName
        self.pinyinInitials = pinyinInitials
    }
}

// Folder to group apps
struct FolderItem: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
    var apps: [AppItem]

    // Cache key for folder icon
    private var iconCacheKey: String {
        apps.prefix(9).map { $0.url.path }.joined(separator: "|")
    }

    var icon: NSImage {
        // Check cache first
        let cacheKey = "folder_\(iconCacheKey)"
        if let cached = FolderIconCache.shared.icon(for: cacheKey) {
            return cached
        }

        // Generate a folder icon from first 9 apps (3x3 grid)
        let size: CGFloat = 128
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        // Draw folder background with border for better visibility
        let folderColor = NSColor.systemGray.withAlphaComponent(0.3)
        let borderColor = NSColor.white.withAlphaComponent(0.3)
        let folderRect = NSRect(x: 2, y: 2, width: size - 4, height: size - 4)
        let folderPath = NSBezierPath(roundedRect: folderRect, xRadius: 20, yRadius: 20)
        folderColor.setFill()
        folderPath.fill()

        // Draw border
        borderColor.setStroke()
        folderPath.lineWidth = 2
        folderPath.stroke()

        // Draw app icons in a 3x3 grid
        let miniSize: CGFloat = 30
        let padding: CGFloat = 12
        let spacing: CGFloat = (size - padding * 2 - miniSize * 3) / 2

        for (index, app) in apps.prefix(9).enumerated() {
            let row = index / 3
            let col = index % 3
            let x = padding + CGFloat(col) * (miniSize + spacing)
            let y = size - padding - miniSize - CGFloat(row) * (miniSize + spacing)
            let rect = NSRect(x: x, y: y, width: miniSize, height: miniSize)
            app.icon.draw(in: rect)
        }

        image.unlockFocus()

        // Cache the result
        FolderIconCache.shared.setIcon(image, for: cacheKey)

        return image
    }

    init(id: UUID = UUID(), name: String, apps: [AppItem]) {
        self.id = id
        self.name = name
        self.apps = apps
    }

    static func == (lhs: FolderItem, rhs: FolderItem) -> Bool {
        lhs.id == rhs.id && lhs.apps.count == rhs.apps.count && lhs.apps.map { $0.id } == rhs.apps.map { $0.id }
    }
}

// Folder icon cache
final class FolderIconCache {
    static let shared = FolderIconCache()
    private var cache: [String: NSImage] = [:]

    private init() {}

    func icon(for key: String) -> NSImage? {
        cache[key]
    }

    func setIcon(_ icon: NSImage, for key: String) {
        cache[key] = icon
    }

    func clearCache() {
        cache.removeAll()
    }
}

// Unified grid item that can be either an app, a folder, or an empty slot
enum LauncherItem: Identifiable, Equatable {
    case app(AppItem)
    case folder(FolderItem)
    case empty(UUID)  // Empty slot placeholder

    var id: UUID {
        switch self {
        case .app(let app): return app.id
        case .folder(let folder): return folder.id
        case .empty(let id): return id
        }
    }

    var name: String {
        switch self {
        case .app(let app): return app.name
        case .folder(let folder): return folder.name
        case .empty: return ""
        }
    }

    var icon: NSImage {
        switch self {
        case .app(let app): return app.icon
        case .folder(let folder): return folder.icon
        case .empty: return NSImage()
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    var asApp: AppItem? {
        if case .app(let app) = self { return app }
        return nil
    }

    var asFolder: FolderItem? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

final class AppScanner {
    static func scan() -> [AppItem] {
        let fm = FileManager.default
        let paths = [
            "/Applications",
            "/System/Applications",
            fm.homeDirectoryForCurrentUser
                .appendingPathComponent("Applications").path
        ]

        var result: [AppItem] = []

        for path in paths {
            guard let urls = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                let pinyinName = pinyin(name).lowercased()
                let initials = pinyinInitials(name).lowercased()
                result.append(AppItem(name: name, url: url, pinyinName: pinyinName, pinyinInitials: initials))
            }
        }

        // Sort by recent use, then by name
        return result.sorted {
            if $0.lastUsed != $1.lastUsed {
                return $0.lastUsed > $1.lastUsed
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

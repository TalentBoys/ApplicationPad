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
        apps.prefix(4).map { $0.url.path }.joined(separator: "|")
    }

    var icon: NSImage {
        // Check cache first
        let cacheKey = "folder_\(iconCacheKey)"
        if let cached = FolderIconCache.shared.icon(for: cacheKey) {
            return cached
        }

        // Generate a folder icon from first 4 apps
        let size: CGFloat = 128
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        // Draw folder background
        let folderColor = NSColor.systemGray.withAlphaComponent(0.3)
        let folderRect = NSRect(x: 0, y: 0, width: size, height: size)
        let folderPath = NSBezierPath(roundedRect: folderRect, xRadius: 20, yRadius: 20)
        folderColor.setFill()
        folderPath.fill()

        // Draw app icons in a 2x2 grid
        let miniSize: CGFloat = 40
        let padding: CGFloat = 12
        let positions = [
            CGPoint(x: padding, y: size - padding - miniSize),
            CGPoint(x: size - padding - miniSize, y: size - padding - miniSize),
            CGPoint(x: padding, y: padding),
            CGPoint(x: size - padding - miniSize, y: padding)
        ]

        for (index, app) in apps.prefix(4).enumerated() {
            let rect = NSRect(x: positions[index].x, y: positions[index].y, width: miniSize, height: miniSize)
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
        lhs.id == rhs.id
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

// Unified grid item that can be either an app or a folder
enum LauncherItem: Identifiable, Equatable {
    case app(AppItem)
    case folder(FolderItem)

    var id: UUID {
        switch self {
        case .app(let app): return app.id
        case .folder(let folder): return folder.id
        }
    }

    var name: String {
        switch self {
        case .app(let app): return app.name
        case .folder(let folder): return folder.name
        }
    }

    var icon: NSImage {
        switch self {
        case .app(let app): return app.icon
        case .folder(let folder): return folder.icon
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
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

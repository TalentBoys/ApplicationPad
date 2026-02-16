//
//  FolderItem.swift
//  LauncherCore
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation
import AppKit

public struct FolderItem: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var apps: [AppItem]

    // Cache key for folder icon
    private var iconCacheKey: String {
        apps.prefix(9).map { $0.url.path }.joined(separator: "|")
    }

    @MainActor
    public var icon: NSImage {
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

    public init(id: UUID = UUID(), name: String, apps: [AppItem]) {
        self.id = id
        self.name = name
        self.apps = apps
    }

    public static func == (lhs: FolderItem, rhs: FolderItem) -> Bool {
        lhs.id == rhs.id && lhs.apps.count == rhs.apps.count && lhs.apps.map { $0.id } == rhs.apps.map { $0.id }
    }
}

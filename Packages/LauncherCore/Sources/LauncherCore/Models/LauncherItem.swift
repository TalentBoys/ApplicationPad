//
//  LauncherItem.swift
//  LauncherCore
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation
import AppKit

// Unified grid item that can be either an app, a folder, or an empty slot
public enum LauncherItem: Identifiable, Equatable {
    case app(AppItem)
    case folder(FolderItem)
    case empty(UUID)  // Empty slot placeholder

    public var id: UUID {
        switch self {
        case .app(let app): return app.id
        case .folder(let folder): return folder.id
        case .empty(let id): return id
        }
    }

    public var name: String {
        switch self {
        case .app(let app): return app.name
        case .folder(let folder): return folder.name
        case .empty: return ""
        }
    }

    @MainActor
    public var icon: NSImage {
        switch self {
        case .app(let app): return app.icon
        case .folder(let folder): return folder.icon
        case .empty: return NSImage()
        }
    }

    public var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }

    public var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    public var asApp: AppItem? {
        if case .app(let app) = self { return app }
        return nil
    }

    public var asFolder: FolderItem? {
        if case .folder(let folder) = self { return folder }
        return nil
    }
}

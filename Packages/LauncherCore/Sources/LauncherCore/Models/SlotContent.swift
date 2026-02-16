//
//  SlotContent.swift
//  LauncherCore
//
//  Content of a grid slot - can be empty, app, or folder
//

import Foundation

public enum SlotContent: Equatable, Sendable {
    case empty
    case app(AppItem)
    case folder(FolderItem)

    public var isEmpty: Bool {
        if case .empty = self { return true }
        return false
    }

    public var isApp: Bool {
        if case .app = self { return true }
        return false
    }

    public var isFolder: Bool {
        if case .folder = self { return true }
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

    public var id: UUID? {
        switch self {
        case .empty: return nil
        case .app(let app): return app.id
        case .folder(let folder): return folder.id
        }
    }
}

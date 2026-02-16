//
//  AppItem.swift
//  LauncherCore
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation
import AppKit

public struct AppItem: Identifiable, Equatable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let url: URL
    public let pinyinName: String      // 完整拼音: wangyiyoudaocidian
    public let pinyinInitials: String  // 首字母: wyydcd

    @MainActor
    public var icon: NSImage {
        IconCache.shared.icon(for: url)
    }

    public var lastUsed: Date {
        UserDefaults.standard.object(forKey: url.path) as? Date ?? .distantPast
    }

    public func markUsed() {
        UserDefaults.standard.set(Date(), forKey: url.path)
    }

    public static func == (lhs: AppItem, rhs: AppItem) -> Bool {
        lhs.url == rhs.url
    }

    public init(id: UUID = UUID(), name: String, url: URL, pinyinName: String, pinyinInitials: String) {
        self.id = id
        self.name = name
        self.url = url
        self.pinyinName = pinyinName
        self.pinyinInitials = pinyinInitials
    }
}

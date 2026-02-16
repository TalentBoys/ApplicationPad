//
//  FolderIconCache.swift
//  LauncherCore
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation
import AppKit

public final class FolderIconCache {
    public static let shared = FolderIconCache()
    private var cache: [String: NSImage] = [:]

    private init() {}

    public func icon(for key: String) -> NSImage? {
        cache[key]
    }

    public func setIcon(_ icon: NSImage, for key: String) {
        cache[key] = icon
    }

    public func clearCache() {
        cache.removeAll()
    }
}

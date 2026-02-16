//
//  IconCache.swift
//  LauncherCore
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation
import AppKit

public final class IconCache {
    public static let shared = IconCache()
    private var cache: [URL: NSImage] = [:]
    private let queue = DispatchQueue(label: "IconCache", attributes: .concurrent)

    // Debug counters
    private var hitCount = 0
    private var missCount = 0

    private init() {}

    public func icon(for url: URL) -> NSImage {
        // Try to get from cache first (read)
        var cachedIcon: NSImage?
        queue.sync {
            cachedIcon = cache[url]
        }

        if let icon = cachedIcon {
            hitCount += 1
            return icon
        }

        missCount += 1
        // Load icon
        let icon = NSWorkspace.shared.icon(forFile: url.path)

        // Store in cache (write)
        queue.async(flags: .barrier) { [weak self] in
            self?.cache[url] = icon
        }

        return icon
    }

    public func logStats() {
        print("📊 IconCache stats - hits: \(hitCount), misses: \(missCount), cached: \(cache.count)")
    }

    public func clearCache() {
        queue.async(flags: .barrier) { [weak self] in
            self?.cache.removeAll()
        }
    }
}

//
//  AppScanner.swift
//  LauncherCore
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation

public final class AppScanner {
    public static func scan() -> [AppItem] {
        let fm = FileManager.default
        let paths = [
            "/Applications",
            "/System/Applications",
        ]

        var result: [AppItem] = []
        var seenURLs = Set<URL>()

        for path in paths {
            guard let urls = try? fm.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "app" {
                guard !seenURLs.contains(url) else { continue }
                seenURLs.insert(url)
                let name = url.deletingPathExtension().lastPathComponent
                let pinyinName = pinyin(name).lowercased()
                let initials = pinyinInitials(name).lowercased()
                result.append(AppItem(name: name, url: url, pinyinName: pinyinName, pinyinInitials: initials))
            }
        }

        // Scan custom directories via security-scoped bookmarks
        let customURLs = LauncherSettings.resolveBookmarks()
        for dirURL in customURLs {
            let accessing = dirURL.startAccessingSecurityScopedResource()
            defer { if accessing { dirURL.stopAccessingSecurityScopedResource() } }

            guard let urls = try? fm.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }

            for url in urls where url.pathExtension == "app" {
                guard !seenURLs.contains(url) else { continue }
                seenURLs.insert(url)
                let name = url.deletingPathExtension().lastPathComponent
                let pinyinName = pinyin(name).lowercased()
                let initials = pinyinInitials(name).lowercased()
                result.append(AppItem(name: name, url: url, pinyinName: pinyinName, pinyinInitials: initials))
            }
        }

        // Sort by recent use, then by name
        result.sort {
            if $0.lastUsed != $1.lastUsed {
                return $0.lastUsed > $1.lastUsed
            }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        // Inject ApplicationPad Settings item
        let settingsName = LauncherCoreStrings.settingsItemName
        result.append(AppItem(
            name: settingsName,
            url: AppItem.settingsURL,
            pinyinName: pinyin(settingsName).lowercased(),
            pinyinInitials: pinyinInitials(settingsName).lowercased()
        ))

        return result
    }
}

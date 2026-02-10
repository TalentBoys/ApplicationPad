//
//  AppScanner.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation
import AppKit

struct AppItem: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    let icon: NSImage
    let pinyinName: String      // 完整拼音: wangyiyoudaocidian
    let pinyinInitials: String  // 首字母: wyydcd

    var lastUsed: Date {
        UserDefaults.standard.object(forKey: url.path) as? Date ?? .distantPast
    }

    func markUsed() {
        UserDefaults.standard.set(Date(), forKey: url.path)
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
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                let pinyinName = pinyin(name).lowercased()
                let initials = pinyinInitials(name).lowercased()
                result.append(AppItem(name: name, url: url, icon: icon, pinyinName: pinyinName, pinyinInitials: initials))
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

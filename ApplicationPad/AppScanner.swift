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
                result.append(AppItem(name: name, url: url, icon: icon))
            }
        }
        return result.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

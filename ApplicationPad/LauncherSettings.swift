//
//  LauncherSettings.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation

struct LauncherSettings {
    static var iconSize: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "iconSize").nonZero ?? 112) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "iconSize") }
    }

    static var columnsCount: Int {
        get { UserDefaults.standard.integer(forKey: "columnsCount").nonZero ?? 6 }
        set { UserDefaults.standard.set(newValue, forKey: "columnsCount") }
    }

    static var rowsCount: Int {
        get { UserDefaults.standard.integer(forKey: "rowsCount").nonZero ?? 5 }
        set { UserDefaults.standard.set(newValue, forKey: "rowsCount") }
    }

    static var horizontalPadding: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "horizontalPadding") as? Double ?? 120) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "horizontalPadding") }
    }

    static var topPadding: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "topPadding") as? Double ?? 30) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "topPadding") }
    }

    static var bottomPadding: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "bottomPadding") as? Double ?? 70) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "bottomPadding") }
    }

    static var invertScroll: Bool {
        get { UserDefaults.standard.bool(forKey: "invertScroll") }
        set { UserDefaults.standard.set(newValue, forKey: "invertScroll") }
    }

    static var scrollSensitivity: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "scrollSensitivity") as? Double ?? 1.0) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "scrollSensitivity") }
    }

    static var appsPerPage: Int {
        columnsCount * rowsCount
    }

    // Custom app order - stores app paths in user-defined order
    static var customAppOrder: [String] {
        get { UserDefaults.standard.stringArray(forKey: "customAppOrder") ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: "customAppOrder") }
    }

    static func saveAppOrder(_ apps: [AppItem]) {
        customAppOrder = apps.map { $0.url.path }
    }

    static func applyCustomOrder(to apps: [AppItem]) -> [AppItem] {
        let order = customAppOrder
        guard !order.isEmpty else {
            // No custom order, sort alphabetically
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        var result: [AppItem] = []
        var remaining = apps

        // First, add apps in saved order
        for path in order {
            if let index = remaining.firstIndex(where: { $0.url.path == path }) {
                result.append(remaining.remove(at: index))
            }
        }

        // Then append any new apps (not in saved order) at the end, sorted alphabetically
        remaining.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        result.append(contentsOf: remaining)

        return result
    }
}

extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}

extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}

//
//  LauncherSettings.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation

struct LauncherSettings {
    static var iconSize: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "iconSize").nonZero ?? 96) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "iconSize") }
    }

    static var columnsCount: Int {
        get { UserDefaults.standard.integer(forKey: "columnsCount").nonZero ?? 8 }
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
        get { CGFloat(UserDefaults.standard.object(forKey: "topPadding") as? Double ?? 20) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "topPadding") }
    }

    static var bottomPadding: CGFloat {
        get { CGFloat(UserDefaults.standard.object(forKey: "bottomPadding") as? Double ?? 40) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "bottomPadding") }
    }

    static var appsPerPage: Int {
        columnsCount * rowsCount
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

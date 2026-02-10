//
//  LauncherSettings.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation

struct LauncherSettings {
    static var windowWidth: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "launcherWidth").nonZero ?? 1400) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "launcherWidth") }
    }

    static var windowHeight: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "launcherHeight").nonZero ?? 900) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "launcherHeight") }
    }

    static var iconSize: CGFloat {
        get { CGFloat(UserDefaults.standard.double(forKey: "iconSize").nonZero ?? 96) }
        set { UserDefaults.standard.set(Double(newValue), forKey: "iconSize") }
    }

    static var columnsCount: Int {
        get { UserDefaults.standard.integer(forKey: "columnsCount").nonZero ?? 6 }
        set { UserDefaults.standard.set(newValue, forKey: "columnsCount") }
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

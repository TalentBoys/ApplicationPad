//
//  Extensions.swift
//  LauncherCore
//
//  Created by Jin, Kris on 2026/2/10.
//

import Foundation

public extension Double {
    var nonZero: Double? {
        self == 0 ? nil : self
    }
}

public extension Int {
    var nonZero: Int? {
        self == 0 ? nil : self
    }
}

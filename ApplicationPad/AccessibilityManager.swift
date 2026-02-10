//
//  AccessibilityManager.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import AppKit
import ApplicationServices

final class AccessibilityManager {

    static func requestPermission() {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary

        AXIsProcessTrustedWithOptions(options)
    }

    static func isGranted() -> Bool {
        AXIsProcessTrusted()
    }
}

//
//  WindowManager.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import AppKit

final class WindowManager {
    static let shared = WindowManager()

    func showLauncher() {
        showWindow(named: "Launcher", floating: true)
    }

    func showMain() {
        showWindow(named: "App Launcher", floating: false)
    }

    private func showWindow(named name: String, floating: Bool) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first(where: { $0.title == name }) {
            window.level = floating ? .floating : .normal
            window.makeKeyAndOrderFront(nil)
            window.center()
        }
    }
}

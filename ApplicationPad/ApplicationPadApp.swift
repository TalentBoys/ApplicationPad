//
//  ApplicationPadApp.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI
import Carbon

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request accessibility permission
        AccessibilityManager.requestPermission()

        // Load saved hotkey settings
        let modifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? (cmdKey | shiftKey)
        let keyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_Space

        // Register global hotkey
        HotKeyManager.shared.register(keyCode: keyCode, modifiers: modifiers) {
            LauncherPanel.shared.toggle()
        }

        // Show launcher on first launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            LauncherPanel.shared.show()
        }
    }

    // Click Dock icon to toggle Launcher
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        LauncherPanel.shared.toggle()
        return false
    }
}

@main
struct ApplicationPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Settings window
        Window("Settings", id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)

        // Menu Bar
        MenuBarExtra("ApplicationPad", image: "MenuBarIcon") {
            Button("Open Launcher") {
                LauncherPanel.shared.show()
            }
            .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            }
            .keyboardShortcut(",", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

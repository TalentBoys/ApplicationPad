//
//  ApplicationPadApp.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI
import Carbon
import LauncherCore

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by ApplicationPadApp to allow opening the settings window
    var openSettingsWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Load saved hotkey settings
        let modifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? (cmdKey | shiftKey)
        let keyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_Space

        // Register global hotkey
        HotKeyManager.shared.register(keyCode: keyCode, modifiers: modifiers) {
            self.showLauncherOrPaywall()
        }

        // Subscription disabled — launch directly
        LauncherPanel.shared.show()
    }

    // Click Dock icon to toggle Launcher
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showLauncherOrPaywall()
        return false
    }

    private func showLauncherOrPaywall() {
        LauncherPanel.shared.toggle()
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
                .onAppear {
                    // Wire up AppDelegate's ability to open this window
                    appDelegate.openSettingsWindow = {
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "settings")
                    }
                }
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

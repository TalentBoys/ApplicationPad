//
//  ApplicationPadApp.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI
import Carbon
import LauncherCore
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate?

    func openSettings() {
        LauncherPanel.shared.showSettings()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.shared = self

        // Initialize localization
        LocalizationManager.shared.updateBundle()
        LocalizationManager.shared.updateCoreStrings()

        // Load saved hotkey settings
        let modifiers = UserDefaults.standard.object(forKey: "hotkeyModifiers") as? Int ?? (cmdKey | shiftKey)
        let keyCode = UserDefaults.standard.object(forKey: "hotkeyKeyCode") as? Int ?? kVK_Space

        // Register global hotkey
        HotKeyManager.shared.register(keyCode: keyCode, modifiers: modifiers) {
            self.showLauncherOrPaywall()
        }

        // Subscription disabled — launch directly
        LauncherPanel.shared.show()

        // Hide Dock icon after UI is ready
        if UserDefaults.standard.bool(forKey: "hideDockIcon") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                NSApp.setActivationPolicy(.accessory)
            }
        }
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
    @State private var localization = LocalizationManager.shared
    @AppStorage("hideMenuBarIcon") private var hideMenuBarIcon: Bool = false

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }

    var body: some Scene {
        // Menu Bar
        MenuBarExtra("ApplicationPad", image: "MenuBarIcon", isInserted: Binding(
            get: { !hideMenuBarIcon },
            set: { hideMenuBarIcon = !$0 }
        )) {
            Button(L("Open Launcher")) {
                LauncherPanel.shared.show()
            }
            .keyboardShortcut("l", modifiers: .command)

            Divider()

            Button(L("Settings...")) {
                LauncherPanel.shared.showSettings()
            }
            .keyboardShortcut(",", modifiers: .command)

            CheckForUpdatesView(updater: updaterController.updater)

            Divider()

            Button(L("Quit")) {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

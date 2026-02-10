//
//  ApplicationPadApp.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request accessibility permission (this makes the app appear in the list)
        AccessibilityManager.requestPermission()

        // Register global hotkey
        HotKeyManager.shared.register {
            WindowManager.shared.showLauncher()
        }

        // Show main window on launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            WindowManager.shared.showMain()
        }
    }
}

@main
struct ApplicationPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main window (auto show on launch)
        WindowGroup("App Launcher") {
            MainView()
        }

        // Launcher window (hidden title bar, for hotkey)
        WindowGroup("Launcher") {
            LauncherView()
        }
        .windowStyle(.hiddenTitleBar)

        // Menu Bar
        MenuBarExtra("ApplicationPad", systemImage: "square.grid.3x3") {
            Button("Open Launcher") {
                WindowManager.shared.showLauncher()
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Open Settings") {
                WindowManager.shared.showMain()
            }
            .keyboardShortcut("s", modifiers: .command)

            Divider()

            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
    }
}

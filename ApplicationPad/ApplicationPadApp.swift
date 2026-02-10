//
//  ApplicationPadApp.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI
import Carbon

// Window identifiers
enum WindowID: String {
    case main = "main"
    case settings = "settings"
}

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
    }
}

struct MenuBarCommands: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack {
            Button("Open Launcher") {
                LauncherPanel.shared.show()
            }
            .keyboardShortcut("l", modifiers: .command)

            Button("Open Main Window") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.main.rawValue)
            }
            .keyboardShortcut("m", modifiers: .command)

            Divider()

            Button("Settings...") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: WindowID.settings.rawValue)
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

// Helper view to open main window on launch
struct WindowOpenerView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    openWindow(id: WindowID.main.rawValue)
                }
            }
    }
}

@main
struct ApplicationPadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Hidden helper window
        WindowGroup("_Helper", id: "_helper") {
            WindowOpenerView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // Main window
        Window("App Launcher", id: WindowID.main.rawValue) {
            MainView()
        }

        // Settings window
        Window("Settings", id: WindowID.settings.rawValue) {
            SettingsView()
        }
        .windowResizability(.contentSize)

        // Menu Bar
        MenuBarExtra("ApplicationPad", image: "MenuBarIcon") {
            MenuBarCommands()
        }
    }
}

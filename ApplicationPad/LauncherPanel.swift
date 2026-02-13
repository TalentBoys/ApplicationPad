//
//  LauncherPanel.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import AppKit
import SwiftUI

class LauncherPanel: NSPanel {
    static let shared = LauncherPanel()

    private var globalClickMonitor: Any?

    private init() {
        super.init(
            contentRect: NSScreen.main?.frame ?? .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .popUpMenu
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        updateContent()
    }

    private func updateContent() {
        let hostingView = NSHostingView(rootView: LauncherContentView())
        self.contentView = hostingView
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        if let screen = NSScreen.main {
            setFrame(screen.frame, display: true)
        }
        updateContent()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        startGlobalClickMonitor()
    }

    override func close() {
        stopGlobalClickMonitor()
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }

    // Monitor clicks outside the panel (on other screens)
    private func startGlobalClickMonitor() {
        stopGlobalClickMonitor()
        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            // Check if click is on a different screen
            guard let self = self, self.isVisible else { return }
            let clickLocation = event.locationInWindow

            // Convert to screen coordinates
            if let screen = NSScreen.screens.first(where: { screen in
                screen.frame.contains(NSPoint(x: clickLocation.x, y: clickLocation.y))
            }) {
                // If click is on a different screen than our panel, close
                if let panelScreen = self.screen, panelScreen != screen {
                    DispatchQueue.main.async {
                        self.close()
                    }
                }
            }
        }
    }

    private func stopGlobalClickMonitor() {
        if let monitor = globalClickMonitor {
            NSEvent.removeMonitor(monitor)
            globalClickMonitor = nil
        }
    }
}

struct LauncherContentView: View {
    var body: some View {
        AppGridView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VisualEffectView())
    }
}

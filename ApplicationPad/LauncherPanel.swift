//
//  LauncherPanel.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import AppKit
import SwiftUI
import Combine

// Shared state for launcher visibility animation
class LauncherAnimationState: ObservableObject {
    static let shared = LauncherAnimationState()
    @Published var isContentVisible = false
}

class LauncherPanel: NSPanel {
    static let shared = LauncherPanel()

    private var globalClickMonitor: Any?

    // Animation state
    private var isAnimating = false

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
        if isVisible && !isAnimating {
            close()
        } else if !isVisible && !isAnimating {
            show()
        }
    }

    func show() {
        guard !isAnimating else { return }
        isAnimating = true

        if let screen = NSScreen.main {
            setFrame(screen.frame, display: true)
        }
        // Reset to invisible state before showing
        LauncherAnimationState.shared.isContentVisible = false
        updateContent()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        startGlobalClickMonitor()

        // Trigger fade-in animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(.easeOut(duration: 0.2)) {
                LauncherAnimationState.shared.isContentVisible = true
            }
            self.isAnimating = false
        }
    }

    override func close() {
        guard !isAnimating else { return }
        isAnimating = true

        stopGlobalClickMonitor()

        // Trigger fade-out animation
        withAnimation(.easeOut(duration: 0.2)) {
            LauncherAnimationState.shared.isContentVisible = false
        }

        // Wait for animation to complete before hiding window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.orderOut(nil)
            self.isAnimating = false
        }
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
    @ObservedObject private var animationState = LauncherAnimationState.shared

    var body: some View {
        AppGridView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VisualEffectView())
            .opacity(animationState.isContentVisible ? 1 : 0)
            .scaleEffect(animationState.isContentVisible ? 1 : 0.95)
    }
}

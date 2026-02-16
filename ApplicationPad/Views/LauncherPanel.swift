//
//  LauncherPanel.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import AppKit
import SwiftUI
import Combine
import LauncherCore

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
        TimingLogger.logWithTimestamp("  📦 updateContent() - creating LauncherContentView...", since: TimingLogger.hotKeyPressedTime)
        let contentView = LauncherContentView()
        TimingLogger.logWithTimestamp("  📦 updateContent() - LauncherContentView created", since: TimingLogger.hotKeyPressedTime)

        TimingLogger.logWithTimestamp("  📦 updateContent() - creating NSHostingView...", since: TimingLogger.hotKeyPressedTime)
        let hostingView = NSHostingView(rootView: contentView)
        TimingLogger.logWithTimestamp("  📦 updateContent() - NSHostingView created", since: TimingLogger.hotKeyPressedTime)

        TimingLogger.logWithTimestamp("  📦 updateContent() - assigning contentView...", since: TimingLogger.hotKeyPressedTime)
        self.contentView = hostingView
        IconCache.shared.logStats()
        TimingLogger.logWithTimestamp("  📦 updateContent() - done", since: TimingLogger.hotKeyPressedTime)
    }

    func toggle() {
        TimingLogger.logWithTimestamp("🔄 toggle() called - isVisible: \(isVisible), isAnimating: \(isAnimating)", since: TimingLogger.hotKeyPressedTime)
        if isVisible && !isAnimating {
            close()
        } else if !isVisible && !isAnimating {
            show()
        }
    }

    func show() {
        TimingLogger.logWithTimestamp("📤 show() START", since: TimingLogger.hotKeyPressedTime)
        guard !isAnimating else {
            TimingLogger.logWithTimestamp("⚠️ show() BLOCKED - already animating")
            return
        }
        isAnimating = true

        if let screen = NSScreen.main {
            setFrame(screen.frame, display: true)
        }
        // Reset to invisible state before showing
        LauncherAnimationState.shared.isContentVisible = false
        TimingLogger.logWithTimestamp("📤 show() - contentVisible set to false", since: TimingLogger.hotKeyPressedTime)

        // 不要每次都重建视图！只在首次或需要时创建
        // updateContent()
        // TimingLogger.logWithTimestamp("📤 show() - updateContent() done", since: TimingLogger.hotKeyPressedTime)

        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        TimingLogger.logWithTimestamp("📤 show() - window made key and front", since: TimingLogger.hotKeyPressedTime)

        startGlobalClickMonitor()

        // Trigger fade-in animation
        TimingLogger.logWithTimestamp("📤 show() - scheduling animation after 0.02s", since: TimingLogger.hotKeyPressedTime)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            TimingLogger.logWithTimestamp("✨ show() - animation block executing", since: TimingLogger.hotKeyPressedTime)
            withAnimation(.easeOut(duration: 0.2)) {
                LauncherAnimationState.shared.isContentVisible = true
                TimingLogger.logWithTimestamp("✨ show() - contentVisible set to true (0.2s animation started)", since: TimingLogger.hotKeyPressedTime)
            }
            self.isAnimating = false
            TimingLogger.logWithTimestamp("📤 show() END - isAnimating = false", since: TimingLogger.hotKeyPressedTime)
        }
    }

    override func close() {
        TimingLogger.logWithTimestamp("📥 close() START", since: TimingLogger.hotKeyPressedTime)
        guard !isAnimating else {
            TimingLogger.logWithTimestamp("⚠️ close() BLOCKED - already animating")
            return
        }
        isAnimating = true

        stopGlobalClickMonitor()

        // Trigger fade-out animation
        TimingLogger.logWithTimestamp("✨ close() - starting fade-out animation (0.2s)", since: TimingLogger.hotKeyPressedTime)
        withAnimation(.easeOut(duration: 0.2)) {
            LauncherAnimationState.shared.isContentVisible = false
        }

        // Wait for animation to complete before hiding window
        TimingLogger.logWithTimestamp("📥 close() - scheduling orderOut after 0.25s", since: TimingLogger.hotKeyPressedTime)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            TimingLogger.logWithTimestamp("📥 close() - orderOut executing", since: TimingLogger.hotKeyPressedTime)
            self.orderOut(nil)
            self.isAnimating = false
            TimingLogger.logWithTimestamp("📥 close() END - window hidden", since: TimingLogger.hotKeyPressedTime)
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

    init() {
        TimingLogger.logWithTimestamp("    🎨 LauncherContentView.init()", since: TimingLogger.hotKeyPressedTime)
    }

    var body: some View {
        let _ = TimingLogger.logWithTimestamp("    🎨 LauncherContentView.body evaluating", since: TimingLogger.hotKeyPressedTime)
        AppGridView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VisualEffectView())
            .opacity(animationState.isContentVisible ? 1 : 0)
            .scaleEffect(animationState.isContentVisible ? 1 : 0.95)
    }
}

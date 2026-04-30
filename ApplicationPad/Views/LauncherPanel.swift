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
import Sparkle

// Shared state for launcher visibility animation
class LauncherAnimationState: ObservableObject {
    static let shared = LauncherAnimationState()
    @Published var isContentVisible = false
    @Published var isClassicMode = false
    @Published var showSettings = false
}

class LauncherPanel: NSPanel {
    static let shared = LauncherPanel()

    private var globalClickMonitor: Any?
    private var deactivationObserver: Any?

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
        self.hidesOnDeactivate = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        updateContent()
    }

    private func updateContent() {
        let contentView = LauncherContentView()
        let hostingView = NSHostingView(rootView: contentView)
        self.contentView = hostingView
    }

    func toggle() {
        if isVisible && !isAnimating {
            if LauncherAnimationState.shared.showSettings {
                LauncherAnimationState.shared.showSettings = false
            } else {
                close()
            }
        } else if !isVisible && !isAnimating {
            show()
        }
    }

    func showSettings() {
        LauncherAnimationState.shared.showSettings = true
        if !isVisible {
            show()
        }
    }

    func show() {
        guard !isAnimating else { return }
//        guard SubscriptionManager.shared.isSubscribed else { return }
        isAnimating = true

        let mouseLocation = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) ?? NSScreen.main
        let isClassic = UserDefaults.standard.string(forKey: "panelStyle") == "classicBlur"

        if let screen = targetScreen {
            // In classic mode, cover the entire screen including menu bar area
            let frame = isClassic ? screen.frame : screen.frame
            setFrame(frame, display: true)
        }

        // Always keep window transparent — DesktopBlurBackground provides the backdrop
        self.backgroundColor = .clear
        self.isOpaque = false

        // Reset to invisible state before showing
        LauncherAnimationState.shared.isContentVisible = false
        LauncherAnimationState.shared.isClassicMode = isClassic

        // First make window visible
        makeKeyAndOrderFront(nil)

        // Only activate app when Dock icon is visible (regular mode).
        // In accessory mode the panel (popUpMenu level) receives events without activation.
        if !UserDefaults.standard.bool(forKey: "hideDockIcon") {
            NSApp.activate(ignoringOtherApps: true)
        }

        startGlobalClickMonitor()
        startDeactivationObserver()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            withAnimation(isClassic ? .easeOut(duration: 0.25) : .easeOut(duration: 0.2)) {
                LauncherAnimationState.shared.isContentVisible = true
            }

            // Ensure window is key after animation starts
            self.makeFirstResponder(self.contentView)

            // After animation completes, make window opaque to fully hide desktop
            let animDuration = isClassic ? 0.25 : 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + animDuration) {
                if isClassic {
                    self.backgroundColor = .black
                    self.isOpaque = true
                }
                self.isAnimating = false
            }
        }
    }

    override func close() {
        let closeStart = CFAbsoluteTimeGetCurrent()
        print("⏱️ [PANEL] close() entered at: \(closeStart)")
        guard !isAnimating else {
            print("⏱️ [PANEL] skipped — already animating")
            return
        }
        isAnimating = true

        stopGlobalClickMonitor()
        stopDeactivationObserver()
        LauncherAnimationState.shared.showSettings = false
        let isClassic = LauncherAnimationState.shared.isClassicMode

        // Restore transparent window before animating out, so zoom-out doesn't show black edges
        self.backgroundColor = .clear
        self.isOpaque = false

        withAnimation(isClassic ? .easeIn(duration: 0.2) : .easeOut(duration: 0.2)) {
            LauncherAnimationState.shared.isContentVisible = false
        }
        print("⏱️ [PANEL] animation started at: \(CFAbsoluteTimeGetCurrent()) (+\(CFAbsoluteTimeGetCurrent() - closeStart)s)")

        // Wait for animation to complete before hiding window
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.orderOut(nil)
            self.isAnimating = false
            print("⏱️ [PANEL] orderOut done at: \(CFAbsoluteTimeGetCurrent()) (+\(CFAbsoluteTimeGetCurrent() - closeStart)s)")
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

    private func startDeactivationObserver() {
        stopDeactivationObserver()
        if UserDefaults.standard.bool(forKey: "hideDockIcon") {
            return
        }
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, self.isVisible else { return }
            self.close()
        }
    }

    private func stopDeactivationObserver() {
        if let observer = deactivationObserver {
            NotificationCenter.default.removeObserver(observer)
            deactivationObserver = nil
        }
    }
}

struct LauncherContentView: View {
    @ObservedObject private var animationState = LauncherAnimationState.shared
    @AppStorage("panelStyle") private var panelStyle: String = "default"

    private var hiddenScale: CGFloat {
        animationState.isClassicMode ? 1.15 : 0.95
    }

    var body: some View {
        AppGridView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(!animationState.showSettings)
            .disabled(animationState.showSettings)
            .overlay {
                if animationState.showSettings {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            animationState.showSettings = false
                        }

                    VStack(spacing: 0) {
                        HStack {
                            Button {
                                animationState.showSettings = false
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chevron.left")
                                    Text(L("Back"))
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                            Spacer()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                        SettingsView(updater: nil)
                    }
                    .frame(width: 580, height: 880)
                    .background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .animation(.easeOut(duration: 0.2), value: animationState.showSettings)
            .background {
                if panelStyle == "classicBlur" {
                    DesktopBlurBackground()
                } else {
                    VisualEffectView()
                }
            }
            .opacity(animationState.isContentVisible ? 1 : 0)
            .scaleEffect(animationState.isContentVisible ? 1 : hiddenScale)
            .preferredColorScheme(panelStyle == "classicBlur" ? .dark : .light)
    }
}

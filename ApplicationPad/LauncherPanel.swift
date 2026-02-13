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
    }

    override func close() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
}

struct LauncherContentView: View {
    var body: some View {
        AppGridView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(VisualEffectView())
    }
}

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
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 500),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hidesOnDeactivate = true

        let hostingView = NSHostingView(rootView: LauncherContentView(panel: self))
        self.contentView = hostingView

        center()
    }

    func toggle() {
        if isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    override func close() {
        orderOut(nil)
    }

    override var canBecomeKey: Bool { true }
}

struct LauncherContentView: View {
    let panel: LauncherPanel

    var body: some View {
        AppGridView(showSettingsHint: false, isLauncher: true)
            .frame(width: 700, height: 500)
            .background(VisualEffectView())
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

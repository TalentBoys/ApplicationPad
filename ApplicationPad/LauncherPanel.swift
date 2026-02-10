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
        let width = LauncherSettings.windowWidth
        let height = LauncherSettings.windowHeight

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
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

        updateContent()
        center()
    }

    func updateSize() {
        let width = LauncherSettings.windowWidth
        let height = LauncherSettings.windowHeight
        setContentSize(NSSize(width: width, height: height))
        updateContent()
        center()
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
        updateSize()
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
    var body: some View {
        AppGridView(showSettingsHint: false, isLauncher: true)
            .frame(
                width: LauncherSettings.windowWidth,
                height: LauncherSettings.windowHeight
            )
            .background(VisualEffectView())
            .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

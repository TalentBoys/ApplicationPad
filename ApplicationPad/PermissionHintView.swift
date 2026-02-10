//
//  PermissionHintView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI
import ApplicationServices

struct PermissionHintView: View {
    @State private var isDismissed = false
    @State private var hasPermission = AXIsProcessTrusted()

    var body: some View {
        if !isDismissed {
            HStack(spacing: 12) {
                Image(systemName: hasPermission ? "checkmark.circle.fill" : "keyboard")
                    .font(.title2)
                    .foregroundColor(hasPermission ? .green : .blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Quick Launch: ⌘ + ⇧ + Space")
                        .font(.headline)

                    if hasPermission {
                        Text("Accessibility permission granted. Hotkey is ready!")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Text("Grant Accessibility permission to enable global hotkey.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if !hasPermission {
                    Button("Request Permission") {
                        requestAccessibilityPermission()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button("Open System Settings") {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                    )
                }
                .buttonStyle(.bordered)

                Button {
                    isDismissed = true
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(.ultraThinMaterial)
            .cornerRadius(10)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .onAppear {
                hasPermission = AXIsProcessTrusted()
            }
        }
    }

    private func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        hasPermission = trusted
    }
}

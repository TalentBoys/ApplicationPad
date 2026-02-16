//
//  SettingsView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI
import Carbon
import LauncherCore

struct SettingsView: View {
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers: Int = cmdKey | shiftKey
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = kVK_Space
    @AppStorage("iconSize") private var iconSize: Double = 112
    @AppStorage("columnsCount") private var columnsCount: Int = 6
    @AppStorage("rowsCount") private var rowsCount: Int = 5
    @AppStorage("horizontalPadding") private var horizontalPadding: Double = 120
    @AppStorage("topPadding") private var topPadding: Double = 30
    @AppStorage("bottomPadding") private var bottomPadding: Double = 70
    @AppStorage("invertScroll") private var invertScroll: Bool = false
    @AppStorage("scrollSensitivity") private var scrollSensitivity: Double = 1.0

    @State private var isRecordingHotkey = false
    @State private var showingResetAlert = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Open Launcher")
                    Spacer()

                    HotkeyRecorderView(
                        isRecording: $isRecordingHotkey,
                        modifiers: $hotkeyModifiers,
                        keyCode: $hotkeyKeyCode
                    ) {
                        HotKeyManager.shared.unregister()
                        HotKeyManager.shared.register(
                            keyCode: hotkeyKeyCode,
                            modifiers: hotkeyModifiers
                        ) {
                            LauncherPanel.shared.toggle()
                        }
                    }
                }

                Button("Reset to Default (⌘ + ⇧ + Space)") {
                    hotkeyModifiers = cmdKey | shiftKey
                    hotkeyKeyCode = kVK_Space
                    HotKeyManager.shared.unregister()
                    HotKeyManager.shared.register(
                        keyCode: hotkeyKeyCode,
                        modifiers: hotkeyModifiers
                    ) {
                        LauncherPanel.shared.toggle()
                    }
                }
                .font(.caption)
            } header: {
                Text("Hotkey")
            }

            Section {
                HStack {
                    Text("Icon Size")
                    Slider(value: $iconSize, in: 48...160, step: 8)
                    Text("\(Int(iconSize))")
                        .frame(width: 50)
                }

                HStack {
                    Text("Columns")
                    Spacer()
                    Picker("", selection: $columnsCount) {
                        ForEach(4...12, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 320)
                }

                HStack {
                    Text("Rows")
                    Spacer()
                    Picker("", selection: $rowsCount) {
                        ForEach(3...8, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                HStack {
                    Text("Horizontal Padding")
                    Slider(value: $horizontalPadding, in: 0...200, step: 10)
                    Text("\(Int(horizontalPadding))")
                        .frame(width: 50)
                }

                HStack {
                    Text("Top Padding")
                    Slider(value: $topPadding, in: 0...200, step: 10)
                    Text("\(Int(topPadding))")
                        .frame(width: 50)
                }

                HStack {
                    Text("Bottom Padding")
                    Slider(value: $bottomPadding, in: 0...200, step: 10)
                    Text("\(Int(bottomPadding))")
                        .frame(width: 50)
                }

                Toggle("Invert Scroll Direction", isOn: $invertScroll)

                HStack {
                    Text("Scroll Sensitivity")
                    Slider(value: $scrollSensitivity, in: 0.5...3.0, step: 0.1)
                    Text(String(format: "%.1f", scrollSensitivity))
                        .frame(width: 50)
                }

                Button("Reset to Default") {
                    iconSize = 112
                    columnsCount = 6
                    rowsCount = 5
                    horizontalPadding = 120
                    topPadding = 30
                    bottomPadding = 70
                    invertScroll = false
                    scrollSensitivity = 1.0
                }
                .font(.caption)
            } header: {
                Text("Appearance")
            }

            Section {
                Button("Reset App Layout") {
                    showingResetAlert = true
                }
                .foregroundColor(.red)
            } header: {
                Text("Layout")
            } footer: {
                Text("This will remove all folders and reset app positions to default alphabetical order.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section {
                LabeledContent("Version", value: Bundle.main.appVersion)
                LabeledContent("Build", value: Bundle.main.buildNumber)
                LabeledContent("Author", value: "Kris Jin")
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 550, height: 650)
        .alert("Reset App Layout", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                LauncherSettings.resetGridLayout()
            }
        } message: {
            Text("This will remove all folders and reset app positions to default alphabetical order. This action cannot be undone.")
        }
    }
}

struct HotkeyRecorderView: View {
    @Binding var isRecording: Bool
    @Binding var modifiers: Int
    @Binding var keyCode: Int
    var onChanged: () -> Void

    @State private var eventMonitor: Any?

    var body: some View {
        HStack {
            Text(isRecording ? "Press shortcut..." : hotkeyString)
                .frame(minWidth: 120)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isRecording ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2))
                .cornerRadius(6)

            Button(isRecording ? "Cancel" : "Change") {
                if isRecording {
                    stopRecording()
                } else {
                    startRecording()
                }
            }
        }
    }

    private var hotkeyString: String {
        var parts: [String] = []
        if modifiers & controlKey != 0 { parts.append("⌃") }
        if modifiers & optionKey != 0 { parts.append("⌥") }
        if modifiers & shiftKey != 0 { parts.append("⇧") }
        if modifiers & cmdKey != 0 { parts.append("⌘") }
        parts.append(keyCodeToString(keyCode))
        return parts.joined()
    }

    private func startRecording() {
        isRecording = true
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let newModifiers = carbonModifiers(from: event.modifierFlags)
            if newModifiers != 0 {
                self.modifiers = newModifiers
                self.keyCode = Int(event.keyCode)
                self.stopRecording()
                self.onChanged()
            }
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return result
    }

    private func keyCodeToString(_ code: Int) -> String {
        switch code {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_Escape: return "⎋"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_ANSI_A...kVK_ANSI_Z:
            let letters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
            let index = [kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_H,
                        kVK_ANSI_G, kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V,
                        0, kVK_ANSI_B, kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R,
                        kVK_ANSI_Y, kVK_ANSI_T, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3,
                        kVK_ANSI_4, kVK_ANSI_6, kVK_ANSI_5, kVK_ANSI_Equal, kVK_ANSI_9,
                        kVK_ANSI_7, kVK_ANSI_Minus, kVK_ANSI_8, kVK_ANSI_0, kVK_ANSI_RightBracket,
                        kVK_ANSI_O, kVK_ANSI_U, kVK_ANSI_LeftBracket, kVK_ANSI_I, kVK_ANSI_P,
                        0, kVK_ANSI_L, kVK_ANSI_J, kVK_ANSI_Quote, kVK_ANSI_K, kVK_ANSI_Semicolon,
                        kVK_ANSI_Backslash, kVK_ANSI_Comma, kVK_ANSI_Slash, kVK_ANSI_N, kVK_ANSI_M]
                .firstIndex(of: code)
            if let idx = index, idx < letters.count {
                return String(letters[letters.index(letters.startIndex, offsetBy: idx)])
            }
            return "?"
        case kVK_ANSI_0...kVK_ANSI_9:
            return "\(code - kVK_ANSI_0)"
        default: return "?"
        }
    }
}

#Preview {
    SettingsView()
}

extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

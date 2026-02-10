//
//  SettingsView.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import SwiftUI
import Carbon

struct SettingsView: View {
    @AppStorage("hotkeyModifiers") private var hotkeyModifiers: Int = cmdKey | shiftKey
    @AppStorage("hotkeyKeyCode") private var hotkeyKeyCode: Int = kVK_Space
    @AppStorage("launcherWidth") private var launcherWidth: Double = 1400
    @AppStorage("launcherHeight") private var launcherHeight: Double = 900
    @AppStorage("iconSize") private var iconSize: Double = 96
    @AppStorage("columnsCount") private var columnsCount: Int = 6

    @State private var isRecordingHotkey = false
    @State private var hasPermission = AccessibilityManager.isGranted()

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Permission Status")
                    Spacer()
                    if hasPermission {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Label("Not Granted", systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }

                if !hasPermission {
                    Button("Request Permission") {
                        AccessibilityManager.requestPermission()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            hasPermission = AccessibilityManager.isGranted()
                        }
                    }

                    Button("Open System Settings") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                        )
                    }
                }
            } header: {
                Text("Accessibility")
            }

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
                    Text("Window Width")
                    Slider(value: $launcherWidth, in: 600...2000, step: 50)
                    Text("\(Int(launcherWidth))")
                        .frame(width: 50)
                }

                HStack {
                    Text("Window Height")
                    Slider(value: $launcherHeight, in: 400...1400, step: 50)
                    Text("\(Int(launcherHeight))")
                        .frame(width: 50)
                }

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
                        ForEach(4...10, id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 280)
                }

                Button("Reset to Default") {
                    launcherWidth = 1400
                    launcherHeight = 900
                    iconSize = 96
                    columnsCount = 6
                    LauncherPanel.shared.updateSize()
                }
                .font(.caption)
            } header: {
                Text("Appearance")
            } footer: {
                Text("Changes apply next time you open the launcher")
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
        .frame(width: 550, height: 550)
        .onAppear {
            hasPermission = AccessibilityManager.isGranted()
        }
        .onChange(of: launcherWidth) { _, _ in LauncherPanel.shared.updateSize() }
        .onChange(of: launcherHeight) { _, _ in LauncherPanel.shared.updateSize() }
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

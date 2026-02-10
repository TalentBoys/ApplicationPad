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

    @State private var isRecordingHotkey = false
    @State private var hasPermission = AccessibilityManager.isGranted()
    @State private var keyMonitor: Any?

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
                        // Re-register hotkey when changed
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
                LabeledContent("Version", value: "1.0.0")
                LabeledContent("Author", value: "Kris Jin")
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .frame(width: 550, height: 400)
        .onAppear {
            hasPermission = AccessibilityManager.isGranted()
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

            // Require at least one modifier
            if newModifiers != 0 {
                self.modifiers = newModifiers
                self.keyCode = Int(event.keyCode)
                self.stopRecording()
                self.onChanged()
            }
            return nil // Consume the event
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
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        default: return "?"
        }
    }
}

#Preview {
    SettingsView()
}

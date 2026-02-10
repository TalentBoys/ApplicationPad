//
//  HotKeyManager.swift
//  ApplicationPad
//
//  Created by Jin, Kris on 2026/2/10.
//

import Cocoa
import Carbon

final class HotKeyManager {
    static let shared = HotKeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private static var callback: (() -> Void)?

    func register(onTrigger: @escaping () -> Void) {
        HotKeyManager.callback = onTrigger

        var eventHotKeyID = EventHotKeyID(
            signature: OSType("APLK".fourCharCode),
            id: 1
        )

        // ⌘ + ⌥ + Space
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | optionKey),
            eventHotKeyID,
            GetEventDispatcherTarget(),
            0,
            &hotKeyRef
        )

        let eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, _ in
                DispatchQueue.main.async {
                    HotKeyManager.callback?()
                }
                return noErr
            },
            1,
            [eventType],
            nil,
            nil
        )
    }
}

extension String {
    var fourCharCode: FourCharCode {
        FourCharCode(utf8.reduce(0) { ($0 << 8) + FourCharCode($1) })
    }
}

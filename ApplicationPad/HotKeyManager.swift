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
    private var eventHandlerRef: EventHandlerRef?
    private static var callback: (() -> Void)?

    func register(
        keyCode: Int = kVK_Space,
        modifiers: Int = cmdKey | optionKey,
        onTrigger: @escaping () -> Void
    ) {
        // Unregister existing hotkey first
        unregister()

        HotKeyManager.callback = onTrigger

        var eventHotKeyID = EventHotKeyID(
            signature: OSType("APLK".fourCharCode),
            id: 1
        )

        RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
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
            &eventHandlerRef
        )
    }

    func unregister() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandlerRef = eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }
}

extension String {
    var fourCharCode: FourCharCode {
        FourCharCode(utf8.reduce(0) { ($0 << 8) + FourCharCode($1) })
    }
}

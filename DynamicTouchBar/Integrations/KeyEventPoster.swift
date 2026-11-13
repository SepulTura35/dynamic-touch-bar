import AppKit
import ApplicationServices

/// Posts the same events the hardware media and brightness keys produce, using public
/// `NSEvent`/`CGEvent` APIs. macOS only accepts synthesized input from apps the user has
/// granted **Accessibility** access, so everything here is opt-in and checked first.
enum KeyEventPoster {
    enum MediaKey: Int {
        // NX_KEYTYPE_* values from IOKit/hidsystem/ev_keymap.h
        case playPause = 16
        case next = 17
        case previous = 18
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security ▸ Accessibility.
    static func requestTrust() {
        let key = "AXTrustedCheckOptionPrompt"
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    static func post(_ key: MediaKey) -> Bool {
        guard isTrusted else { return false }
        postSystemDefined(keyType: key.rawValue, down: true)
        postSystemDefined(keyType: key.rawValue, down: false)
        return true
    }

    private static func postSystemDefined(keyType: Int, down: Bool) {
        let flags = NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00)
        let data1 = (keyType << 16) | ((down ? 0xA : 0xB) << 8)
        let event = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: data1,
            data2: -1
        )
        event?.cgEvent?.post(tap: .cghidEventTap)
    }

    /// Brightness up/down virtual key codes (the F14/F15-position "brightness" keys).
    enum BrightnessKey: CGKeyCode {
        case up = 144
        case down = 145
    }

    @discardableResult
    static func post(_ key: BrightnessKey) -> Bool {
        guard isTrusted else { return false }
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: key.rawValue, keyDown: false)?.post(tap: .cghidEventTap)
        return true
    }
}

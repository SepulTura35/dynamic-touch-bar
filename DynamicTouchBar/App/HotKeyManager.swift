import Carbon.HIToolbox
import Foundation

/// Global shortcut via the public Carbon Event Manager `RegisterEventHotKey` API.
/// Unlike global key monitors, this needs no Accessibility permission and never sees any
/// other keystrokes.
final class HotKeyManager {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: (() -> Void)?
    private static let signature: OSType = 0x4454_426B // 'DTBk'

    deinit {
        // Unregistered explicitly via unregister(); Carbon refs are released there.
    }

    @discardableResult
    func register(_ preset: HotKeyPreset, handler: @escaping () -> Void) -> Bool {
        unregister()
        guard let definition = preset.carbonDefinition else { return true }
        self.handler = handler

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard hotKeyID.signature == HotKeyManager.signature else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { manager.handler?() }
            return noErr
        }, 1, &eventType, context, &handlerRef)

        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let registerStatus = RegisterEventHotKey(definition.keyCode, definition.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        let ok = installStatus == noErr && registerStatus == noErr
        if !ok {
            Log.app.error("Could not register hot key \(preset.title, privacy: .public) (status \(registerStatus)) — it may be in use by another app")
        }
        return ok
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
        hotKeyRef = nil
        handlerRef = nil
        handler = nil
    }
}

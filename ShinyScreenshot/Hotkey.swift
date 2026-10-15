import Carbon.HIToolbox

/// A global keyboard shortcut. Carbon hot keys need no Accessibility permission.
final class Hotkey {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?
    /// False when another app already owns the shortcut.
    private(set) var isRegistered = false

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        Self.installHandler()
        let id = UInt32(Self.actions.count + 1)
        Self.actions[id] = action
        isRegistered = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: OSType(0x5348_4E59), id: id),
                                           GetApplicationEventTarget(), 0, &ref) == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        isRegistered = false
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var key = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            let id = key.id
            // Carbon delivers application events on the main thread.
            MainActor.assumeIsolated { Hotkey.actions[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

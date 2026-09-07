import Carbon

/// Registers only the chosen chord, rather than observing arbitrary keystrokes.
@MainActor
final class PlayerShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let keyCode: UInt32
    private let modifiers: UInt32
    private let id: UInt32
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, id: UInt32, action: @escaping () -> Void) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.id = id
        self.action = action
    }

    func register() -> Bool {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x43485253 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<PlayerShortcut>.fromOpaque(context).takeUnretainedValue()
            guard id.id == shortcut.id else { return OSStatus(eventNotHandledErr) }
            // Carbon dispatches application events on the main event loop.
            MainActor.assumeIsolated { shortcut.action() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        let registered = RegisterEventHotKey(keyCode, modifiers,
                                            EventHotKeyID(signature: 0x43485253, id: id),
                                            GetApplicationEventTarget(), 0, &hotKey) == noErr
        if !registered { unregister() }
        return registered
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

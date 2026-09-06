import Carbon

/// Registers only the chosen chord, rather than observing arbitrary keystrokes.
@MainActor
final class PlayerShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void

    init(action: @escaping () -> Void) { self.action = action }

    func register() -> Bool {
        unregister()
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x43485253, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<PlayerShortcut>.fromOpaque(context).takeUnretainedValue()
            // Carbon dispatches application events on the main event loop.
            MainActor.assumeIsolated { shortcut.action() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return false }
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey | controlKey),
                                            EventHotKeyID(signature: 0x43485253, id: 1),
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

import Carbon

@MainActor
final class RecoveryShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: () -> Void = {}

    func register(action: @escaping () -> Void) {
        self.action = action
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<RecoveryShortcut>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in shortcut.action() }
            return noErr
        }, 1, &event, Unmanaged.passUnretained(self).toOpaque(), &handler)
        let identifier = EventHotKeyID(signature: 0x4C534352, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey | cmdKey), identifier,
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

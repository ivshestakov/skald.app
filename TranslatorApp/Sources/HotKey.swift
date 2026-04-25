import Carbon.HIToolbox

struct HotKeyModifiers: OptionSet {
    let rawValue: UInt32
    static let command = HotKeyModifiers(rawValue: UInt32(cmdKey))
    static let shift   = HotKeyModifiers(rawValue: UInt32(shiftKey))
    static let option  = HotKeyModifiers(rawValue: UInt32(optionKey))
    static let control = HotKeyModifiers(rawValue: UInt32(controlKey))
}

/// Registers a process-wide global hotkey via Carbon's RegisterEventHotKey.
/// Carbon is the only API that gives you a real key-grab that works while
/// another app is frontmost — the modern NSEvent monitor APIs don't cover
/// the "activate my app from nothing" case reliably.
final class HotKey {

    private var ref: EventHotKeyRef?
    private let id: UInt32

    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    init?(keyCode: UInt32, modifiers: HotKeyModifiers, handler: @escaping () -> Void) {
        Self.installHandlerIfNeeded()

        let newID = Self.nextID
        Self.nextID += 1
        self.id = newID

        let signature: OSType = 0x5452_4E53 // 'TRNS'
        let eventID = EventHotKeyID(signature: signature, id: newID)

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            keyCode,
            modifiers.rawValue,
            eventID,
            GetApplicationEventTarget(),
            0,
            &ref
        )

        guard status == noErr, let ref else { return nil }
        self.ref = ref
        Self.handlers[newID] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        Self.handlers[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                guard let event else { return noErr }
                var hk = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hk
                )
                if err == noErr {
                    HotKey.handlers[hk.id]?()
                }
                return noErr
            },
            1,
            &spec,
            nil,
            nil
        )
    }
}

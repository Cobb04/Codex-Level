import Carbon.HIToolbox

struct CodexLevelShortcut: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = CodexLevelShortcut(
        keyCode: UInt32(kVK_ANSI_L),
        modifiers: UInt32(optionKey))

    @MainActor
    func perform(_ action: () -> Void) {
        action()
    }
}

enum PopoverToggleAction: Equatable, Sendable {
    case show
    case close

    static func next(isPopoverShown: Bool) -> Self {
        isPopoverShown ? .close : .show
    }
}

enum GlobalHotKeyError: Error {
    case eventHandler(OSStatus)
    case registration(OSStatus)
}

final class GlobalHotKey: @unchecked Sendable {
    private static let identifier = EventHotKeyID(signature: 0x4364_4C76, id: 1) // CdLv

    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private let shortcut: CodexLevelShortcut
    private let action: @MainActor () -> Void

    @MainActor
    init(
        shortcut: CodexLevelShortcut = .default,
        action: @escaping @MainActor () -> Void
    ) throws {
        self.shortcut = shortcut
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            codexLevelHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler)
        guard handlerStatus == noErr else {
            throw GlobalHotKeyError.eventHandler(handlerStatus)
        }

        let registrationStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            Self.identifier,
            GetApplicationEventTarget(),
            0,
            &hotKey)
        guard registrationStatus == noErr else {
            if let eventHandler {
                RemoveEventHandler(eventHandler)
                self.eventHandler = nil
            }
            throw GlobalHotKeyError.registration(registrationStatus)
        }
    }

    deinit {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    @MainActor
    fileprivate func handle(_ identifier: EventHotKeyID) {
        guard identifier.signature == Self.identifier.signature,
              identifier.id == Self.identifier.id
        else { return }
        shortcut.perform(action)
    }
}

private let codexLevelHotKeyHandler: EventHandlerUPP = { _, event, context in
    guard let event, let context else { return OSStatus(eventNotHandledErr) }

    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier)
    guard status == noErr else { return status }

    let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated {
        hotKey.handle(identifier)
    }
    return noErr
}

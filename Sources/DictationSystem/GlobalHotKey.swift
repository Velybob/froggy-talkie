import Carbon
import Foundation

@MainActor
public final class GlobalHotKey {
    private var hotKey: EventHotKeyRef?
    private var registeredShortcut: DictationShortcut?
    private var eventHandler: EventHandlerRef?
    private let pressed: @MainActor () -> Void
    private let released: @MainActor () -> Void
    private static let signature: OSType = 0x4C444354 // LDCT

    public init(pressed: @escaping @MainActor () -> Void, released: @escaping @MainActor () -> Void) {
        self.pressed = pressed
        self.released = released
    }

    public func register(shortcut: DictationShortcut = .default) throws {
        guard shortcut.isValid else { throw RegistrationError(shortcut: shortcut, status: OSStatus(paramErr)) }
        if registeredShortcut == shortcut, hotKey != nil { return }
        if eventHandler == nil { try installHandler() }
        var replacement: EventHotKeyRef?
        let registration = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: 1), GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive), &replacement)
        guard registration == noErr else {
            // A failed replacement must not remove the working shortcut.
            if hotKey == nil { unregister() }
            throw RegistrationError(shortcut: shortcut, status: registration)
        }
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        registeredShortcut = shortcut
    }

    private func installHandler() throws {
        var types = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr else { return status }
            // Carbon delivers application-target events on the main event loop.
            return MainActor.assumeIsolated {
                let owner = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
                guard identifier.signature == GlobalHotKey.signature, identifier.id == 1 else {
                    return OSStatus(eventNotHandledErr)
                }
                switch GetEventKind(event) {
                case UInt32(kEventHotKeyPressed): owner.pressed()
                case UInt32(kEventHotKeyReleased): owner.released()
                default: return OSStatus(eventNotHandledErr)
                }
                return noErr
            }
        }, types.count, &types, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        guard status == noErr else { throw RegistrationError(shortcut: .default, status: status) }
    }

    public func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKey = nil
        registeredShortcut = nil
        eventHandler = nil
    }

    private struct RegistrationError: LocalizedError {
        let shortcut: DictationShortcut
        let status: OSStatus
        var errorDescription: String? { "Не удалось зарегистрировать \(shortcut.display) (код \(status)). Возможно, сочетание занято." }
    }
}

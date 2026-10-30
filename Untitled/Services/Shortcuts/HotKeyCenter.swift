import Carbon.HIToolbox
import OSLog

/// Registers system-wide hot keys with Carbon's event manager, which needs no
/// Accessibility or Input Monitoring permission. One instance lives as long as the app.
final class HotKeyCenter {
    enum RegistrationError: LocalizedError {
        case alreadyTaken
        case failed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .alreadyTaken: String(localized: "Another app already uses this shortcut.")
            case .failed(let status): String(localized: "macOS couldn't register this shortcut (error \(status)).")
            }
        }
    }

    private struct Registration {
        let reference: EventHotKeyRef
        let action: () -> Void
    }

    private static let signature: OSType = 0x554E_544C // "UNTL"

    private var registrations: [UInt32: Registration] = [:]
    private var nextID: UInt32 = 1
    private var handler: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
        if status != noErr {
            Log.app.error("Installing the hot key handler failed: \(status)")
        }
    }

    /// Registers a shortcut and returns an identifier for unregistering it.
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) throws(RegistrationError) -> UInt32 {
        let id = nextID
        nextID += 1
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            0,
            &reference
        )
        guard status == noErr, let reference else {
            throw status == OSStatus(eventHotKeyExistsErr) ? .alreadyTaken : .failed(status)
        }
        registrations[id] = Registration(reference: reference, action: action)
        return id
    }

    func unregisterAll() {
        for registration in registrations.values {
            UnregisterEventHotKey(registration.reference)
        }
        registrations.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        registrations[id]?.action()
    }
}

/// Carbon calls this on the main thread when a registered hot key is pressed.
private nonisolated func hotKeyEventHandler(
    _ callReference: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    guard status == noErr else { return status }
    let id = hotKeyID.id
    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    MainActor.assumeIsolated {
        center.fire(id)
    }
    return noErr
}

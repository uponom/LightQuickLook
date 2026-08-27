import Carbon.HIToolbox
import os

private final class CarbonCallbackContext: @unchecked Sendable {
    let event: EventRef
    let userData: UnsafeMutableRawPointer

    init(event: EventRef, userData: UnsafeMutableRawPointer) {
        self.event = event
        self.userData = userData
    }
}

private final class CarbonRegistrationState: @unchecked Sendable {
    var eventHandler: EventHandlerRef?
    var hotKeys: [EventHotKeyRef] = []
}

@MainActor
final class FontSizeHotKeyMonitor {
    enum Action: UInt32, Equatable {
        case decrease = 1
        case increase = 2
    }

    struct Shortcut: Equatable {
        let action: Action
        let keyCode: UInt32
        let modifiers: UInt32
        let identifier: UInt32
    }

    static let signature: OSType = 0x4C_51_4C_4B // LQLK
    static let shortcuts = [
        Shortcut(
            action: .decrease,
            keyCode: UInt32(kVK_ANSI_Minus),
            modifiers: UInt32(cmdKey),
            identifier: Action.decrease.rawValue
        ),
        Shortcut(
            action: .increase,
            keyCode: UInt32(kVK_ANSI_Equal),
            modifiers: UInt32(cmdKey | shiftKey),
            identifier: Action.increase.rawValue
        ),
        // Many macOS apps also accept Command-= as the unshifted form of Command-+.
        Shortcut(
            action: .increase,
            keyCode: UInt32(kVK_ANSI_Equal),
            modifiers: UInt32(cmdKey),
            identifier: Action.increase.rawValue
        ),
    ]

    private static let logger = Logger(
        subsystem: "io.github.uponom.LightQuickLook.Preview",
        category: "FontSizeHotKeys"
    )
    private static let carbonEventHandler: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        let context = CarbonCallbackContext(event: event, userData: userData)
        return MainActor.assumeIsolated {
            let monitor = Unmanaged<FontSizeHotKeyMonitor>
                .fromOpaque(context.userData)
                .takeUnretainedValue()
            return monitor.handle(event: context.event)
        }
    }

    private let registration = CarbonRegistrationState()
    private let actionHandler: (Action) -> Void

    private(set) var registrationStatuses: [OSStatus] = []

    var isRunning: Bool {
        registration.eventHandler != nil && registration.hotKeys.count == Self.shortcuts.count
    }

    init(actionHandler: @escaping (Action) -> Void) {
        self.actionHandler = actionHandler
    }

    @discardableResult
    func start() -> Bool {
        if isRunning { return true }
        stop()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var installedHandler: EventHandlerRef?
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            Self.carbonEventHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &installedHandler
        )
        guard handlerStatus == noErr, let installedHandler else {
            registrationStatuses = [handlerStatus]
            Self.logger.error("Unable to install font-size hotkey handler: \(handlerStatus)")
            return false
        }
        registration.eventHandler = installedHandler

        registrationStatuses = Self.shortcuts.map(register)
        guard registration.hotKeys.count == Self.shortcuts.count else {
            Self.logger.error(
                "Unable to register every font-size hotkey. Statuses: \(self.registrationStatuses.description, privacy: .public)"
            )
            stop(preservingStatuses: true)
            return false
        }

        Self.logger.info("Registered Command-minus and Command-plus font-size hotkeys")
        return true
    }

    func stop() {
        stop(preservingStatuses: false)
    }

    @discardableResult
    func route(signature: OSType, identifier: UInt32) -> Bool {
        guard signature == Self.signature, let action = Action(rawValue: identifier) else { return false }
        actionHandler(action)
        return true
    }

    private func register(_ shortcut: Shortcut) -> OSStatus {
        var hotKey: EventHotKeyRef?
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            EventHotKeyID(signature: Self.signature, id: shortcut.identifier),
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyNoOptions),
            &hotKey
        )
        if status == noErr, let hotKey {
            registration.hotKeys.append(hotKey)
        }
        return status
    }

    private func handle(event: EventRef) -> OSStatus {
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
        guard route(signature: hotKeyID.signature, identifier: hotKeyID.id) else {
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }

    private func stop(preservingStatuses: Bool) {
        for hotKey in registration.hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        registration.hotKeys.removeAll()

        if let eventHandler = registration.eventHandler {
            RemoveEventHandler(eventHandler)
            registration.eventHandler = nil
        }
        if !preservingStatuses {
            registrationStatuses = []
        }
    }

    deinit {
        for hotKey in registration.hotKeys {
            UnregisterEventHotKey(hotKey)
        }
        if let eventHandler = registration.eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}

import AppKit
import Carbon
import Foundation

/// Global ⌥M hotkey for start/stop meeting.
/// Uses Carbon RegisterEventHotKey — more reliable for Option+letter
/// shortcuts than inspecting CGEvent taps.
final class MeetingHotKeyMonitor: @unchecked Sendable {
    var onToggle: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x464E4454), id: 1) // 'FNDT'

    func start() throws {
        guard hotKeyRef == nil else { return }

        var handler: EventHandlerRef?
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return noErr }
                var eventHotKeyID = EventHotKeyID()
                let err = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &eventHotKeyID
                )
                guard err == noErr else { return noErr }

                let monitor = Unmanaged<MeetingHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                if eventHotKeyID.signature == monitor.hotKeyID.signature,
                   eventHotKeyID.id == monitor.hotKeyID.id
                {
                    DispatchQueue.main.async {
                        monitor.onToggle?()
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )

        guard status == noErr else {
            throw HotKeyError.handlerFailed(status)
        }
        handlerRef = handler

        var ref: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_M),
            UInt32(optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard registerStatus == noErr, let ref else {
            if let handlerRef {
                RemoveEventHandler(handlerRef)
                self.handlerRef = nil
            }
            throw HotKeyError.registerFailed(registerStatus)
        }
        hotKeyRef = ref
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }

    enum HotKeyError: LocalizedError {
        case handlerFailed(OSStatus)
        case registerFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .handlerFailed(let status):
                return "Could not install meeting hotkey handler (\(status))."
            case .registerFailed(let status):
                return "Could not register ⌥M meeting hotkey (\(status)). Another app may be using it."
            }
        }
    }
}

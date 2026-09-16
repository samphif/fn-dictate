import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation

/// Monitors the Globe/Fn key (and Ctrl+Opt fallback) for push-to-talk.
final class FnKeyMonitor: @unchecked Sendable {
    enum Event {
        case holdBegan
        case holdEnded
        case cancel
    }

    var onEvent: ((Event) -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var fnDownAt: Date?
    private var ctrlOptDownAt: Date?
    private var activeHold: ActiveHold?
    private let holdThreshold: TimeInterval = 0.45

    private enum ActiveHold {
        case fn
        case ctrlOpt
    }

    func start() throws {
        guard eventTap == nil else { return }

        let mask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<FnKeyMonitor>.fromOpaque(userInfo).takeUnretainedValue()
            return monitor.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw MonitorError.tapCreateFailed
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        fnDownAt = nil
        ctrlOptDownAt = nil
        activeHold = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == kVK_Escape {
            if activeHold != nil {
                cancelHold()
                return nil
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        if keyCode == Int64(kVK_Function) {
            let isDown = flags.contains(.maskSecondaryFn)
            return handleFn(isDown: isDown, event: event)
        }

        let ctrlOptDown = flags.contains(.maskControl) && flags.contains(.maskAlternate)
            && !flags.contains(.maskCommand) && !flags.contains(.maskShift)

        if keyCode == Int64(kVK_Control) || keyCode == Int64(kVK_RightControl)
            || keyCode == Int64(kVK_Option) || keyCode == Int64(kVK_RightOption)
        {
            return handleCtrlOpt(isDown: ctrlOptDown, event: event)
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFn(isDown: Bool, event: CGEvent) -> Unmanaged<CGEvent>? {
        if isDown {
            guard activeHold == nil else { return nil }
            fnDownAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold) { [weak self] in
                guard let self, let started = self.fnDownAt, self.activeHold == nil else { return }
                if Date().timeIntervalSince(started) >= self.holdThreshold - 0.01 {
                    self.activeHold = .fn
                    self.onEvent?(.holdBegan)
                }
            }
            return nil
        }

        let started = fnDownAt
        fnDownAt = nil
        if activeHold == .fn {
            activeHold = nil
            onEvent?(.holdEnded)
            return nil
        }

        if let started, Date().timeIntervalSince(started) < holdThreshold {
            // Short tap — let system keep Fn for function-key remaps; we already swallowed down.
            return Unmanaged.passUnretained(event)
        }
        return Unmanaged.passUnretained(event)
    }

    private func handleCtrlOpt(isDown: Bool, event: CGEvent) -> Unmanaged<CGEvent>? {
        if isDown {
            guard activeHold == nil, ctrlOptDownAt == nil else {
                return Unmanaged.passUnretained(event)
            }
            ctrlOptDownAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold) { [weak self] in
                guard let self, let started = self.ctrlOptDownAt, self.activeHold == nil else { return }
                if Date().timeIntervalSince(started) >= self.holdThreshold - 0.01 {
                    self.activeHold = .ctrlOpt
                    self.onEvent?(.holdBegan)
                }
            }
            return Unmanaged.passUnretained(event)
        }

        let started = ctrlOptDownAt
        ctrlOptDownAt = nil
        if activeHold == .ctrlOpt {
            activeHold = nil
            onEvent?(.holdEnded)
            return nil
        }

        _ = started
        return Unmanaged.passUnretained(event)
    }

    private func cancelHold() {
        fnDownAt = nil
        ctrlOptDownAt = nil
        activeHold = nil
        onEvent?(.cancel)
    }

    enum MonitorError: Error {
        case tapCreateFailed
    }
}

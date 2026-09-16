import AppKit
import Carbon.HIToolbox
import Foundation

/// Monitors the Globe/Fn key (and Ctrl+Opt fallback) for:
/// - Hold → push-to-talk
/// - Double-tap → hands-free toggle
/// - Single-tap → stop hands-free (when already listening)
///
/// Uses `NSEvent` global + local monitors (Accessibility) instead of a `CGEvent`
/// tap. Input Monitoring + ad-hoc Xcode signing is brittle: every rebuild changes
/// the CDHash and TCC treats the binary as a new app.
final class FnKeyMonitor: @unchecked Sendable {
    enum Event {
        case holdBegan
        case holdEnded
        case cancel
        case doubleTap
        case singleTap
    }

    var onEvent: ((Event) -> Void)?

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fnDownAt: Date?
    private var ctrlOptDownAt: Date?
    private var activeHold: ActiveHold?
    private let holdThreshold: TimeInterval = 0.45
    private let doubleTapWindow: TimeInterval = 0.35

    private var tapCount = 0
    private var firstTapAt: Date?
    private var singleTapWorkItem: DispatchWorkItem?

    private enum ActiveHold {
        case fn
        case ctrlOpt
    }

    func start() throws {
        guard globalMonitor == nil, localMonitor == nil else { return }

        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }

        guard globalMonitor != nil, localMonitor != nil else {
            stop()
            throw MonitorError.monitorCreateFailed
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        resetTapState()
        fnDownAt = nil
        ctrlOptDownAt = nil
        activeHold = nil
    }

    private func handle(_ event: NSEvent) {
        if event.type == .keyDown {
            if Int(event.keyCode) == kVK_Escape {
                if activeHold != nil || tapCount > 0 {
                    cancelHold()
                    return
                }
                onEvent?(.cancel)
            }
            return
        }

        guard event.type == .flagsChanged else { return }

        let keyCode = Int(event.keyCode)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if keyCode == kVK_Function {
            let isDown = flags.contains(.function)
            handleFn(isDown: isDown)
            return
        }

        let ctrlOptDown = flags.contains(.control) && flags.contains(.option)
            && !flags.contains(.command) && !flags.contains(.shift)

        if keyCode == kVK_Control || keyCode == kVK_RightControl
            || keyCode == kVK_Option || keyCode == kVK_RightOption
        {
            handleCtrlOpt(isDown: ctrlOptDown)
        }
    }

    private func handleFn(isDown: Bool) {
        if isDown {
            guard activeHold == nil else { return }
            fnDownAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold) { [weak self] in
                guard let self, let started = self.fnDownAt, self.activeHold == nil else { return }
                if Date().timeIntervalSince(started) >= self.holdThreshold - 0.01 {
                    self.resetTapState()
                    self.activeHold = .fn
                    self.onEvent?(.holdBegan)
                }
            }
            return
        }

        let started = fnDownAt
        fnDownAt = nil
        if activeHold == .fn {
            activeHold = nil
            onEvent?(.holdEnded)
            return
        }

        if let started, Date().timeIntervalSince(started) < holdThreshold {
            registerTap()
        }
    }

    private func handleCtrlOpt(isDown: Bool) {
        if isDown {
            guard activeHold == nil, ctrlOptDownAt == nil else { return }
            ctrlOptDownAt = Date()
            DispatchQueue.main.asyncAfter(deadline: .now() + holdThreshold) { [weak self] in
                guard let self, let started = self.ctrlOptDownAt, self.activeHold == nil else { return }
                if Date().timeIntervalSince(started) >= self.holdThreshold - 0.01 {
                    self.resetTapState()
                    self.activeHold = .ctrlOpt
                    self.onEvent?(.holdBegan)
                }
            }
            return
        }

        let started = ctrlOptDownAt
        ctrlOptDownAt = nil
        if activeHold == .ctrlOpt {
            activeHold = nil
            onEvent?(.holdEnded)
            return
        }

        if let started, Date().timeIntervalSince(started) < holdThreshold {
            registerTap()
        }
    }

    private func registerTap() {
        let now = Date()
        if let firstTapAt, now.timeIntervalSince(firstTapAt) <= doubleTapWindow {
            tapCount += 1
        } else {
            tapCount = 1
            firstTapAt = now
        }

        singleTapWorkItem?.cancel()

        if tapCount >= 2 {
            resetTapState()
            onEvent?(.doubleTap)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self, self.tapCount == 1 else { return }
            self.resetTapState()
            self.onEvent?(.singleTap)
        }
        singleTapWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + doubleTapWindow, execute: work)
    }

    private func resetTapState() {
        singleTapWorkItem?.cancel()
        singleTapWorkItem = nil
        tapCount = 0
        firstTapAt = nil
    }

    private func cancelHold() {
        resetTapState()
        fnDownAt = nil
        ctrlOptDownAt = nil
        activeHold = nil
        onEvent?(.cancel)
    }

    enum MonitorError: Error {
        case monitorCreateFailed
    }
}

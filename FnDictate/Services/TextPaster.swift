import AppKit
import ApplicationServices
import Foundation

enum TextPaster {
    static func frontmostApp() -> (bundleID: String?, name: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }

    /// Frontmost app that can receive a paste. Skips Fn Dictate and system overlays
    /// (Siri, Spotlight, Visual Intelligence) and falls back to the last real app.
    @MainActor
    static func frontmostTargetApp() -> NSRunningApplication? {
        resolvedPasteTarget(preferred: NSWorkspace.shared.frontmostApplication)
    }

    /// App to paste into. `preferred` wins when it is a real editor; otherwise the
    /// last app the user was in before Siri (or our own UI) covered it.
    @MainActor
    static func resolvedPasteTarget(preferred: NSRunningApplication?) -> NSRunningApplication? {
        if let preferred, isPasteDestination(preferred) {
            return preferred
        }
        if let front = NSWorkspace.shared.frontmostApplication, isPasteDestination(front) {
            return front
        }
        return PasteMemory.app
    }

    /// True for Siri, Spotlight, Visual Intelligence, and other chrome that must not eat ⌘V.
    static func isSystemOverlay(_ app: NSRunningApplication?) -> Bool {
        guard let app else { return false }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        let id = (app.bundleIdentifier ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        if name == "siri" || name == "spotlight" { return true }
        let markers = ["siri", "spotlight", "visualintelligence"]
        if markers.contains(where: { id.contains($0) }) { return true }
        let chrome: Set<String> = [
            "com.apple.controlcenter",
            "com.apple.notificationcenterui",
            "com.apple.systemuiserver",
            "com.apple.dock",
            "com.apple.windowmanager",
            "com.apple.loginwindow",
        ]
        return chrome.contains(id)
    }

    /// Keep the last real app and its editable field so a later Siri popup can paste back.
    @MainActor
    static func startRememberingPasteTarget() {
        captureFocusedFieldIfEligible()
        guard PasteMemory.timer == nil else { return }
        let timer = Timer(timeInterval: 0.8, repeats: true) { _ in
            Task { @MainActor in
                captureFocusedFieldIfEligible()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        PasteMemory.timer = timer
    }

    @MainActor
    static func noteActivated(_ app: NSRunningApplication?) {
        guard let app, isPasteDestination(app) else { return }
        PasteMemory.app = app
        captureFocusedFieldIfEligible()
    }

    /// Snapshot the focused editable field when a real app is frontmost.
    /// A non-field focus in that app drops a stale caret so we don't jump back to it.
    @MainActor
    static func captureFocusedFieldIfEligible() {
        guard let front = NSWorkspace.shared.frontmostApplication, isPasteDestination(front) else { return }
        PasteMemory.app = front
        if let focus = FocusedTextReader.editableFocus(), focus.pid == front.processIdentifier {
            PasteMemory.element = focus.element
            PasteMemory.pid = focus.pid
        } else if PasteMemory.pid == front.processIdentifier {
            PasteMemory.element = nil
            PasteMemory.pid = 0
        }
    }

    @MainActor
    static func rememberedField(pid: pid_t) -> AXUIElement? {
        guard PasteMemory.pid == pid, let element = PasteMemory.element else { return nil }
        return element
    }

    /// Escape dismisses the Siri / Visual Intelligence composer so it doesn't take ⌘V.
    static func dismissSystemOverlayIfNeeded() {
        guard isSystemOverlay(NSWorkspace.shared.frontmostApplication) else { return }
        postKey(0x35)
    }

    @MainActor
    static func focusRememberedField(pid: pid_t) {
        guard let element = rememberedField(pid: pid) else { return }
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    }

    private static func isPasteDestination(_ app: NSRunningApplication) -> Bool {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
        return !isSystemOverlay(app)
    }

    private static func postKey(_ keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyDown?.flags = flags
        keyUp?.flags = flags
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    /// Bring `app` forward so ⌘V lands in the field the user was editing.
    @MainActor
    @discardableResult
    static func activate(_ app: NSRunningApplication?) -> Bool {
        guard let app, !app.isTerminated else { return false }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier { return false }
        // Cooperative activation (macOS 14+): yield if we're frontmost, then request activate.
        if NSApp.isActive {
            NSApp.yieldActivation(to: app)
        }
        return app.activate()
    }

    static func paste(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        if let previousString {
            let pasted = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let current = NSPasteboard.general.string(forType: .string)
                // Only restore if our paste string is still on the clipboard.
                guard current == pasted else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(previousString, forType: .string)
            }
        }
    }
}

/// Last real editor, remembered so a Siri popup doesn't become the paste target.
@MainActor
private enum PasteMemory {
    static var app: NSRunningApplication?
    static var element: AXUIElement?
    static var pid: pid_t = 0
    static var timer: Timer?
}

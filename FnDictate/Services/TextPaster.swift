import AppKit
import Foundation

enum TextPaster {
    static func frontmostApp() -> (bundleID: String?, name: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }

    /// Frontmost app excluding Fn Dictate itself (useful when our UI briefly activates).
    static func frontmostTargetApp() -> NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        if let front, front.bundleIdentifier != Bundle.main.bundleIdentifier {
            return front
        }
        return nil
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

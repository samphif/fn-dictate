import AppKit
import ApplicationServices
import Foundation

enum TextPaster {
    static func frontmostApp() -> (bundleID: String?, name: String?) {
        let app = NSWorkspace.shared.frontmostApplication
        return (app?.bundleIdentifier, app?.localizedName)
    }

    static func paste(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let previousString = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        if let previousString {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(previousString, forType: .string)
            }
        }
    }
}

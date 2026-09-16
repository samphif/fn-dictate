import AppKit
import ApplicationServices
import Foundation

/// Reads the macOS Accessibility focused text field (Wispr-style app context).
enum FocusedTextReader {
    struct Snapshot: Equatable, Sendable {
        let value: String
        let isSecure: Bool
        let pid: pid_t
        let role: String?
    }

    /// Focused UI element + text snapshot, or nil when Accessibility can't see a text field.
    static func readFocused() -> (element: AXUIElement, snapshot: Snapshot)? {
        guard let element = focusedElement() else { return nil }
        guard let snapshot = snapshot(of: element) else { return nil }
        return (element, snapshot)
    }

    static func snapshot(of element: AXUIElement) -> Snapshot? {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != 0 else { return nil }

        let role = stringAttribute(element, kAXRoleAttribute as String)
        let subrole = stringAttribute(element, kAXSubroleAttribute as String)
        // Role constant varies by SDK; match the accessibility role string directly.
        let isSecure =
            role == "AXSecureTextField"
            || role?.localizedCaseInsensitiveContains("secure") == true
            || subrole?.localizedCaseInsensitiveContains("secure") == true

        // Prefer AXValue; some web fields only expose selected text.
        let value =
            stringAttribute(element, kAXValueAttribute as String)
            ?? stringAttribute(element, kAXSelectedTextAttribute as String)
            ?? ""

        return Snapshot(value: value, isSecure: isSecure, pid: pid, role: role)
    }

    static func isSameElement(_ a: AXUIElement, _ b: AXUIElement) -> Bool {
        CFEqual(a, b)
    }

    // MARK: - Private

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &ref
        ) == .success,
            let ref
        else { return nil }
        return (ref as! AXUIElement)
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let ref
        else { return nil }
        if let string = ref as? String { return string }
        if let number = ref as? NSNumber { return number.stringValue }
        return nil
    }
}

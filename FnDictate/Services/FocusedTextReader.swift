import AppKit
import ApplicationServices
import Foundation

/// Reads the macOS Accessibility focused text field (Wispr-style app context).
/// Walks ancestors/children because Electron apps (Cursor, Slack, VS Code) often
/// focus a wrapper with an empty AXValue while the real text lives nearby.
enum FocusedTextReader {
    struct Snapshot: Equatable, Sendable {
        let value: String
        let isSecure: Bool
        let pid: pid_t
        let role: String?
    }

    /// Best-effort focused text: focused element, then nearby editable nodes.
    static func readFocused() -> (element: AXUIElement, snapshot: Snapshot)? {
        guard let focused = focusedElement() else { return nil }
        return readBest(around: focused)
    }

    /// Prefer an element whose value contains `needle` (e.g. just-pasted dictation).
    static func readFocused(containing needle: String) -> (element: AXUIElement, snapshot: Snapshot)? {
        guard let focused = focusedElement() else { return nil }
        if let match = readBest(around: focused, containing: needle) {
            return match
        }
        return nil
    }

    /// Prefer editable text that still looks like an edit of `reference` (not UI chrome).
    static func readFocused(preferringSimilarTo reference: String) -> (element: AXUIElement, snapshot: Snapshot)? {
        guard let focused = focusedElement() else { return nil }
        if let match = readBest(around: focused, containing: reference) {
            return match
        }
        return readBest(around: focused, similarTo: reference)
    }

    static func snapshot(of element: AXUIElement) -> Snapshot? {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        guard pid != 0 else { return nil }

        let role = stringAttribute(element, kAXRoleAttribute as String)
        let subrole = stringAttribute(element, kAXSubroleAttribute as String)
        let isSecure =
            role == "AXSecureTextField"
            || role?.localizedCaseInsensitiveContains("secure") == true
            || subrole?.localizedCaseInsensitiveContains("secure") == true

        let value = extractValue(from: element)

        return Snapshot(value: value, isSecure: isSecure, pid: pid, role: role)
    }

    static func isSameElement(_ a: AXUIElement, _ b: AXUIElement) -> Bool {
        CFEqual(a, b)
    }

    /// Focused editable field, if Accessibility can see one.
    static func editableFocus() -> (element: AXUIElement, pid: pid_t)? {
        guard let reading = readFocused(), isEditableRole(reading.snapshot.role) else { return nil }
        return (reading.element, reading.snapshot.pid)
    }

    // MARK: - Tree search

    private static func readBest(
        around focused: AXUIElement,
        containing needle: String? = nil,
        similarTo reference: String? = nil
    ) -> (element: AXUIElement, snapshot: Snapshot)? {
        var best: (element: AXUIElement, snapshot: Snapshot)?
        var bestScore = -1

        func consider(_ element: AXUIElement) {
            guard let snap = snapshot(of: element), !snap.isSecure else { return }
            let score = score(snapshot: snap, needle: needle, similarTo: reference)
            guard score > bestScore else { return }
            bestScore = score
            best = (element, snap)
        }

        consider(focused)

        // Descend a few levels — Chromium often nests AXTextArea under the focused node.
        for child in descendants(of: focused, maxDepth: 4, limit: 40) {
            consider(child)
        }

        // Climb ancestors and scan their children (focused wrapper → sibling textarea).
        var ancestor: AXUIElement? = focused
        for _ in 0..<6 {
            guard let current = ancestor else { break }
            consider(current)
            for child in children(of: current).prefix(20) {
                consider(child)
                for grand in children(of: child).prefix(12) {
                    consider(grand)
                }
            }
            ancestor = parent(of: current)
        }

        // Require non-empty when searching for paste content.
        if let needle, !needle.isEmpty {
            guard let best, best.snapshot.value.contains(needle)
                    || collapse(best.snapshot.value).contains(collapse(needle))
            else { return nil }
        } else if let reference, !reference.isEmpty {
            // Similarity search must beat "random nearby chrome" — require real overlap.
            guard bestScore >= 120, let best, !best.snapshot.value.isEmpty else { return nil }
        } else {
            guard let best, !best.snapshot.value.isEmpty else { return nil }
        }
        return best
    }

    private static func score(
        snapshot: Snapshot,
        needle: String?,
        similarTo reference: String? = nil
    ) -> Int {
        let value = snapshot.value
        guard !value.isEmpty else { return -1 }

        var score = 0
        if isEditableRole(snapshot.role) { score += 50 }

        if reference != nil {
            // When matching an edit of our paste, prefer compact fields over long
            // chat transcripts — length is a weak signal next to token overlap.
            score += max(0, 40 - min(value.count, 800) / 20)
        } else {
            // Mild preference for substantive editable content (not empty chrome).
            score += min(value.count, 400) / 20
        }

        if let needle, !needle.isEmpty {
            if value.contains(needle) {
                score += 500
            } else if collapse(value).contains(collapse(needle)) {
                score += 300
            } else {
                return -1
            }
        }

        if let reference, !reference.isEmpty {
            let overlap = tokenOverlap(reference, value)
            if overlap < 0.45 {
                return -1
            }
            score += Int(overlap * 400)
            // Penalize wholesale replacement with a much shorter/longer string.
            let ratio = Double(value.count) / Double(max(reference.count, 1))
            if ratio < 0.35 || ratio > 2.8 {
                return -1
            }
            score += Int((1.0 - abs(1.0 - min(ratio, 2.0))) * 40)
        }
        return score
    }

    private static func tokenOverlap(_ a: String, _ b: String) -> Double {
        let left = Set(tokens(a))
        let right = Set(tokens(b))
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        let inter = left.intersection(right).count
        let union = left.union(right).count
        return Double(inter) / Double(union)
    }

    private static func tokens(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { $0.count >= 2 }
    }

    private static func isEditableRole(_ role: String?) -> Bool {
        guard let role else { return false }
        let editable = ["AXTextArea", "AXTextField", "AXComboBox", "AXSearchField"]
        return editable.contains(role)
    }

    private static func extractValue(from element: AXUIElement) -> String {
        if let value = stringAttribute(element, kAXValueAttribute as String), !value.isEmpty {
            return value
        }
        if let selected = stringAttribute(element, kAXSelectedTextAttribute as String), !selected.isEmpty {
            return selected
        }
        // Some Electron fields expose attributed strings.
        if let attributed = attributedStringAttribute(element, kAXValueAttribute as String), !attributed.isEmpty {
            return attributed
        }
        // Last resort: concatenate static-text children (rare, but helps some web views).
        let joined = children(of: element)
            .compactMap { stringAttribute($0, kAXValueAttribute as String) }
            .filter { !$0.isEmpty }
            .joined(separator: "")
        return joined
    }

    // MARK: - AX helpers

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

    private static func parent(of element: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXParentAttribute as CFString,
            &ref
        ) == .success,
            let ref
        else { return nil }
        return (ref as! AXUIElement)
    }

    private static func children(of element: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXChildrenAttribute as CFString,
            &ref
        ) == .success,
            let array = ref as? [AXUIElement]
        else { return [] }
        return array
    }

    private static func descendants(
        of root: AXUIElement,
        maxDepth: Int,
        limit: Int
    ) -> [AXUIElement] {
        var results: [AXUIElement] = []
        var queue: [(AXUIElement, Int)] = children(of: root).map { ($0, 1) }
        while let (node, depth) = queue.first {
            queue.removeFirst()
            results.append(node)
            if results.count >= limit { break }
            if depth < maxDepth {
                for child in children(of: node) {
                    queue.append((child, depth + 1))
                    if results.count + queue.count >= limit { break }
                }
            }
        }
        return results
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

    private static func attributedStringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let attributed = ref as? NSAttributedString
        else { return nil }
        return attributed.string
    }

    private static func collapse(_ text: String) -> String {
        text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

import AppKit
import ApplicationServices
import Foundation

/// Best-effort Accessibility roster of meeting participants (Wispr/Granola-style).
/// Reads display names from Zoom / Meet / Teams UI — does not bind active speaker turns.
enum MeetingParticipantReader {
    struct Roster: Equatable, Sendable {
        var names: [String]
        var sourceAppName: String?
    }

    /// Scan running meeting apps (and browsers) for participant-like AX titles.
    static func readRoster(
        preferredAppName: String? = nil,
        preferredBundleID: String? = nil
    ) -> Roster {
        guard AXIsProcessTrusted() else {
            return Roster(names: [], sourceAppName: preferredAppName)
        }

        let running = NSWorkspace.shared.runningApplications
        var candidates: [(app: NSRunningApplication, rank: Int)] = []

        for app in running {
            guard let bid = app.bundleIdentifier else { continue }
            let rank = rankApp(
                bundleID: bid,
                preferredBundleID: preferredBundleID,
                preferredAppName: preferredAppName,
                appName: preferredAppName
            )
            if rank >= 0 {
                candidates.append((app, rank))
            }
        }

        candidates.sort { $0.rank < $1.rank }

        for entry in candidates {
            let names = collectNames(from: entry.app)
            if !names.isEmpty {
                let label = displayName(for: entry.app) ?? preferredAppName
                return Roster(names: names, sourceAppName: label)
            }
        }

        return Roster(names: [], sourceAppName: preferredAppName)
    }

    // MARK: - App ranking

    private static func rankApp(
        bundleID: String,
        preferredBundleID: String?,
        preferredAppName: String?,
        appName: String?
    ) -> Int {
        if let preferredBundleID, bundleID == preferredBundleID { return 0 }

        let family = (preferredAppName ?? appName)?.lowercased() ?? ""
        if family.contains("zoom"), bundleID.contains("zoom") { return 1 }
        if family.contains("teams"), bundleID.contains("teams") || isBrowser(bundleID) { return 1 }
        if family.contains("meet") || family.contains("google"), isBrowser(bundleID) { return 1 }

        if bundleID.contains("zoom") { return 5 }
        if bundleID.contains("teams") { return 5 }
        if isBrowser(bundleID) { return 8 }
        return -1
    }

    private static func isBrowser(_ bundleID: String) -> Bool {
        let ids: Set<String> = [
            "com.microsoft.edgemac",
            "com.google.Chrome",
            "company.thebrowser.Browser",
            "com.apple.Safari",
            "com.brave.Browser",
            "org.mozilla.firefox"
        ]
        return ids.contains(bundleID)
    }

    private static func displayName(for app: NSRunningApplication) -> String? {
        if let bid = app.bundleIdentifier {
            if bid.contains("zoom") { return "Zoom" }
            if bid.contains("teams") { return "Teams" }
            if bid == "com.microsoft.edgemac" { return "Edge" }
            if isBrowser(bid) { return app.localizedName ?? "Browser" }
        }
        return app.localizedName
    }

    // MARK: - AX walk

    private static func collectNames(from app: NSRunningApplication) -> [String] {
        let pid = app.processIdentifier
        let appElement = AXUIElementCreateApplication(pid)
        var collected: [String] = []
        var seen = Set<String>()

        func consider(_ raw: String) {
            let cleaned = cleanName(raw)
            guard isPlausibleParticipantName(cleaned) else { return }
            let key = cleaned.lowercased()
            guard seen.insert(key).inserted else { return }
            collected.append(cleaned)
        }

        walk(appElement, depth: 0, maxDepth: 10, budget: 400, visit: &collected) { element in
            if let title = stringAttribute(element, kAXTitleAttribute as String) {
                consider(title)
            }
            if let desc = stringAttribute(element, kAXDescriptionAttribute as String) {
                consider(desc)
            }
            if let value = stringAttribute(element, kAXValueAttribute as String), value.count < 80 {
                // Some Electron UIs put the display name in AXValue on tiles.
                if looksLikePersonLabel(value) {
                    consider(value)
                }
            }
        }

        return Array(collected.prefix(24))
    }

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        budget: inout Int,
        visit: (AXUIElement) -> Void
    ) {
        guard budget > 0, depth <= maxDepth else { return }
        budget -= 1
        visit(element)

        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement]
        else { return }

        for child in children.prefix(40) {
            walk(child, depth: depth + 1, maxDepth: maxDepth, budget: &budget, visit: visit)
            if budget <= 0 { return }
        }
    }

    private static func stringAttribute(_ element: AXUIElement, _ name: String) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success,
              let value = ref as? String
        else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func cleanName(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip common tile suffixes: "Alex (Muted)", "Alex — presenting"
        if let range = s.range(of: #"\s*[\(\[—\-].*"#, options: .regularExpression) {
            let head = String(s[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
            if isPlausibleParticipantName(head) {
                s = head
            }
        }
        return s
    }

    private static func looksLikePersonLabel(_ value: String) -> Bool {
        let lower = value.lowercased()
        if lower.contains("http") || lower.contains("www.") { return false }
        if value.count > 60 { return false }
        return isPlausibleParticipantName(value)
    }

    private static func isPlausibleParticipantName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, trimmed.count <= 48 else { return false }

        let lower = trimmed.lowercased()
        let blocked: Set<String> = [
            "you", "others", "mute", "unmute", "share", "chat", "leave", "participants",
            "people", "meeting", "gallery", "speaker view", "reactions", "apps", "more",
            "microsoft teams", "zoom", "google meet", "invite", "copy link", "settings",
            "microphone", "camera", "video", "audio", "recording", "stop", "start",
            "search", "filter", "close", "minimize", "maximize", "ok", "cancel",
            "yes", "no", "done", "edit", "delete", "add", "remove", "raise hand"
        ]
        if blocked.contains(lower) { return false }
        if lower.hasPrefix("http") { return false }
        if trimmed.allSatisfy({ $0.isNumber || $0.isPunctuation || $0.isWhitespace }) {
            return false
        }

        // Prefer 1–4 word human-looking labels (allows "Alex Kim", "Dr. Smith").
        let words = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard (1...4).contains(words.count) else { return false }
        let letterCount = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        return letterCount >= 2
    }
}

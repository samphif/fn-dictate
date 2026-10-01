import AppKit
import ApplicationServices
import Foundation

/// Best-effort Accessibility roster of meeting participants (Wispr/Granola-style).
/// Reads display names from Zoom / Meet / Teams UI — does not bind active speaker turns.
///
/// Only meeting windows are walked. The app element also exposes the menu bar,
/// and that menu was being stored as a roster: About This Mac, Recent Items,
/// “Show in Finder”, and Documents.
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

        var budget = 400
        // Windows only. The application element also exposes the menu bar.
        for root in windowElements(appElement).prefix(6) {
            walk(root, depth: 0, maxDepth: 10, budget: &budget) { element in
                // Window and toolbar titles repeat the call chrome ("Calendar | Microsoft Teams").
                guard includesOwnLabel(element) else { return }
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
            if budget <= 0 { break }
        }

        return Array(collected.prefix(24))
    }

    private static func windowElements(_ appElement: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement]
        else { return [] }
        return windows
    }

    private static func walk(
        _ element: AXUIElement,
        depth: Int,
        maxDepth: Int,
        budget: inout Int,
        visit: (AXUIElement) -> Void
    ) {
        guard budget > 0, depth <= maxDepth else { return }
        // Apple menu, Recent Items, and app menus are not participants.
        if isMenuChrome(element) { return }
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

    /// Roster entries safe to show as speaker suggestions or feed to naming.
    /// Drops menu-bar and window-chrome strings already saved on older notes.
    static func usableNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in names {
            let cleaned = cleanName(name)
            guard isPlausibleParticipantName(cleaned) else { continue }
            guard seen.insert(cleaned.lowercased()).inserted else { continue }
            out.append(cleaned)
        }
        return out
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
        // "Jodi | Guest" → Jodi. "Calendar | Microsoft Teams" stays intact and is rejected.
        if let pipe = s.firstIndex(of: "|") {
            let head = String(s[..<pipe]).trimmingCharacters(in: .whitespacesAndNewlines)
            if isPlausibleParticipantName(head) {
                s = head
            }
        }
        return s
    }

    private static func role(of element: AXUIElement) -> String? {
        stringAttribute(element, kAXRoleAttribute as String)
    }

    private static func isMenuChrome(_ element: AXUIElement) -> Bool {
        guard let role = role(of: element) else { return false }
        let chrome: Set<String> = [
            kAXMenuBarRole as String,
            kAXMenuBarItemRole as String,
            kAXMenuRole as String,
            kAXMenuItemRole as String
        ]
        return chrome.contains(role)
    }

    /// Structural containers whose own title is chrome, not a person. Children are still walked.
    private static func includesOwnLabel(_ element: AXUIElement) -> Bool {
        guard let role = role(of: element) else { return true }
        let structural: Set<String> = [
            kAXApplicationRole as String,
            kAXWindowRole as String,
            kAXSheetRole as String,
            kAXDrawerRole as String,
            kAXToolbarRole as String,
            kAXScrollAreaRole as String
        ]
        return !structural.contains(role)
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
            "yes", "no", "done", "edit", "delete", "add", "remove", "raise hand",
            // Browser / AX chrome (Meet-in-Edge etc.)
            "edge", "chrome", "safari", "firefox", "brave", "arc",
            "app bar", "address and search bar", "view site information",
            "refresh", "back", "forward", "workspaces", "factset profile",
            "new tab", "tabs", "favorites", "history", "downloads", "extensions",
            "bookmarks", "reading list", "collections", "profile", "profiles",
            "window", "windows", "toolbar", "sidebar", "omnibox", "address bar",
            "reload", "home", "menu", "file", "view", "help",
            "share screen", "present now", "turn on captions", "turn off captions",
            "leave call", "end call", "admit", "deny", "waiting room",
            // Apple menu, Recent Items, and the Teams window title.
            "apple", "about this mac", "system information", "system settings",
            "app store", "recent items", "applications", "calendar",
            "force quit", "lock screen", "log out", "sleep", "restart", "shut down",
            "documents", "desktop", "recents", "airdrop",
            "icloud drive", "macintosh hd", "servers", "clear menu",
            "pictures", "movies", "music", "locations"
        ]
        if blocked.contains(lower) { return false }
        if lower.hasPrefix("http") { return false }
        // Menu items and Spotlight/Finder rows: "1Password.app", "Show \"FnDictate.app\" in Finder".
        if lower.contains(".app") || lower.contains("in finder") || lower.contains("\"") || lower.contains("“") {
            return false
        }
        if trimmed.contains("|") || trimmed.contains("…") || trimmed.contains("...") { return false }
        if lower.range(of: #"\d+\s+updates?"#, options: .regularExpression) != nil { return false }
        // Phrases that often appear as AX titles for chrome, not people.
        let blockedSubstrings = [
            "search bar", "address bar", "site information", "app bar",
            "new tab", "tab group", "view site", "this mac", "system settings"
        ]
        if blockedSubstrings.contains(where: { lower.contains($0) }) { return false }
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

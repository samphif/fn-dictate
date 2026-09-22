import Foundation

/// Short labels for the history app badge (fixed-width column).
enum AppDisplayName {
    private static let browserBundleIDs: Set<String> = [
        "com.microsoft.edgemac",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.apple.Safari",
        "com.brave.Browser",
        "org.mozilla.firefox"
    ]

    /// Prefer bundle ID when known; otherwise strip common vendor prefixes.
    static func short(name: String?, bundleID: String?) -> String {
        if let bundleID, let mapped = shortName(forBundleID: bundleID) {
            return mapped
        }
        guard let name, !name.isEmpty else { return "Unknown" }
        return shortened(from: name)
    }

    /// Meeting call source for notes: "Zoom", "Teams", "Teams · Edge (Work)", "Google Meet · Chrome".
    static func meetingSource(appName: String?, bundleID: String?, detail: String? = nil) -> String? {
        let trimmedName = appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedName.isEmpty || !(bundleID ?? "").isEmpty else { return nil }

        let service: String = {
            if !trimmedName.isEmpty { return shortened(from: trimmedName) }
            if let bundleID, let mapped = shortName(forBundleID: bundleID) { return mapped }
            return "Call"
        }()

        guard let bundleID, browserBundleIDs.contains(bundleID) else {
            return service
        }

        let browser = shortName(forBundleID: bundleID) ?? short(name: nil, bundleID: bundleID)
        if let profile = browserProfile(fromWindowTitle: detail, bundleID: bundleID) {
            return "\(service) · \(browser) (\(profile))"
        }
        return "\(service) · \(browser)"
    }

    /// Edge/Chrome often encode the profile in the window title trailing segment.
    static func browserProfile(fromWindowTitle title: String?, bundleID: String?) -> String? {
        guard let title, !title.isEmpty, let bundleID else { return nil }
        let patterns: [(bundle: String, regex: String)] = [
            ("com.microsoft.edgemac", #"\s-\s(.+?)\s-\sMicrosoft\s+Edge\s*$"#),
            ("com.google.Chrome", #"\s-\s(.+?)\s-\sGoogle\s+Chrome\s*$"#),
            ("com.brave.Browser", #"\s-\s(.+?)\s-\sBrave\s*$"#),
            ("org.mozilla.firefox", #"\s-\s(.+?)\s-\sMozilla\s+Firefox\s*$"#)
        ]
        guard let match = patterns.first(where: { $0.bundle == bundleID }),
              let regex = try? NSRegularExpression(pattern: match.regex, options: .caseInsensitive),
              let result = regex.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              result.numberOfRanges > 1,
              let nameRange = Range(result.range(at: 1), in: title)
        else {
            return nil
        }
        var profile = String(title[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        // Single-profile windows often omit a real profile and only show the browser name.
        let blocked = ["microsoft edge", "google chrome", "brave", "mozilla firefox", "safari", "arc"]
        if profile.isEmpty || blocked.contains(profile.lowercased()) { return nil }
        if profile.count > 40 { profile = String(profile.prefix(37)) + "…" }
        return profile
    }

    private static func shortName(forBundleID bundleID: String) -> String? {
        switch bundleID {
        case "com.microsoft.edgemac":
            return "Edge"
        case "com.microsoft.teams", "com.microsoft.teams2", "com.microsoft.teams.mac":
            return "Teams"
        case "com.google.Chrome":
            return "Chrome"
        case "com.brave.Browser":
            return "Brave"
        case "org.mozilla.firefox":
            return "Firefox"
        case "company.thebrowser.Browser":
            return "Arc"
        case "com.apple.Safari":
            return "Safari"
        case "com.apple.Notes":
            return "Notes"
        case "com.apple.mail":
            return "Mail"
        case "com.tinyspeck.slackmacgap":
            return "Slack"
        case "com.hnc.Discord":
            return "Discord"
        case "us.zoom.xos", "zoom.us":
            return "Zoom"
        case "com.microsoft.Word":
            return "Word"
        case "com.microsoft.Excel":
            return "Excel"
        case "com.microsoft.Powerpoint":
            return "PowerPoint"
        case "com.microsoft.Outlook":
            return "Outlook"
        case "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders":
            return "VS Code"
        default:
            return nil
        }
    }

    private static func shortened(from name: String) -> String {
        let prefixes = ["Microsoft ", "Google ", "Apple "]
        for prefix in prefixes where name.hasPrefix(prefix) && name.count > prefix.count {
            return String(name.dropFirst(prefix.count))
        }
        return name
    }
}

import Foundation

/// Short labels for the history app badge (fixed-width column).
enum AppDisplayName {
    /// Prefer bundle ID when known; otherwise strip common vendor prefixes.
    static func short(name: String?, bundleID: String?) -> String {
        if let bundleID, let mapped = shortName(forBundleID: bundleID) {
            return mapped
        }
        guard let name, !name.isEmpty else { return "Unknown" }
        return shortened(from: name)
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

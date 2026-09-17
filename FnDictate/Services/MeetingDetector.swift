import AppKit
import Foundation

struct DetectedMeeting: Equatable, Sendable {
    let appName: String
    let bundleID: String
    let detail: String

    /// Stable id for dismiss / re-prompt — strips unread badges like "(2)" so chat
    /// title flicker doesn't look like a new meeting.
    var fingerprint: String {
        let normalized = Self.normalizeDetail(detail)
        return "\(appName)|\(normalized)"
    }

    private static func normalizeDetail(_ detail: String) -> String {
        var s = detail
        if let regex = try? NSRegularExpression(pattern: #"^\(\d+\)\s*"#) {
            s = regex.stringByReplacingMatches(
                in: s,
                range: NSRange(s.startIndex..., in: s),
                withTemplate: ""
            )
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

/// Watches for Zoom / Teams / Meet / Webex / FaceTime and surfaces a prompt
/// when a meeting appears to be in progress — Wispr-style "meeting recognized".
@MainActor
final class MeetingDetector {
    var onMeetingDetected: ((DetectedMeeting) -> Void)?
    /// Fired when a previously confirmed call is no longer visible (or dismissed).
    var onMeetingEnded: ((DetectedMeeting) -> Void)?

    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastDetected: DetectedMeeting?
    /// Bundle IDs the user dismissed (cleared when that app family quits or snooze ends).
    private var dismissedBundleIDs: Set<String> = []
    private var dismissedFingerprints: Set<String> = []
    /// App-family → don't re-prompt until this date (Not now).
    private var snoozedFamiliesUntil: [String: Date] = [:]
    /// Require a few consistent scans so flaky window titles don't flap the UI.
    private var positiveStreak = 0
    private var negativeStreak = 0
    private var pendingDetection: DetectedMeeting?
    private let confirmHits = 2
    private let confirmMisses = 3
    private let snoozeDuration: TimeInterval = 45 * 60

    private let knownApps: [(bundleID: String, name: String)] = [
        ("us.zoom.xos", "Zoom"),
        ("zoom.us", "Zoom"),
        ("com.microsoft.teams2", "Teams"),
        ("com.microsoft.teams", "Teams"),
        ("com.microsoft.teams.mac", "Teams"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.cisco.webexmeetingsapp", "Webex"),
        ("com.webex.meetingmanager", "Webex"),
        ("com.hnc.Discord", "Discord"),
        ("com.tinyspeck.slackmacgap", "Slack")
    ]

    private let browserBundleIDs: Set<String> = [
        "com.microsoft.edgemac",
        "com.google.Chrome",
        "company.thebrowser.Browser",
        "com.apple.Safari",
        "com.brave.Browser",
        "org.mozilla.firefox"
    ]

    func start() {
        stop()
        observeWorkspace()
        timer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.scan()
            }
        }
        timer?.tolerance = 0.5
        scan()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
    }

    func dismissCurrent() {
        let ended = lastDetected
        if let ended {
            let family = Self.appFamily(for: ended.bundleID, appName: ended.appName)
            dismissedFingerprints.insert(ended.fingerprint)
            // Snooze the whole app family so title flicker can't re-prompt immediately.
            snoozedFamiliesUntil[family] = Date().addingTimeInterval(snoozeDuration)
            for bid in Self.bundleIDs(inFamily: family) {
                dismissedBundleIDs.insert(bid)
            }
        }
        lastDetected = nil
        pendingDetection = nil
        positiveStreak = 0
        negativeStreak = 0
        if let ended {
            onMeetingEnded?(ended)
        }
    }

    func clearDismissal(for bundleID: String) {
        dismissedBundleIDs.remove(bundleID)
        let family = Self.appFamily(for: bundleID, appName: nil)
        snoozedFamiliesUntil.removeValue(forKey: family)
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.scan()
                }
            }
            workspaceObservers.append(observer)
        }
    }

    private func scan() {
        pruneDismissalsAgainstRunningApps()

        let running = NSWorkspace.shared.runningApplications
        let raw = detectMeeting(from: running)

        if let raw {
            negativeStreak = 0
            if pendingDetection?.fingerprint == raw.fingerprint {
                positiveStreak += 1
            } else {
                pendingDetection = raw
                positiveStreak = 1
            }

            guard positiveStreak >= confirmHits else { return }
            guard !isSuppressed(raw) else { return }

            if lastDetected?.fingerprint != raw.fingerprint {
                lastDetected = raw
                onMeetingDetected?(raw)
            }
        } else {
            positiveStreak = 0
            pendingDetection = nil
            negativeStreak += 1
            if let ended = lastDetected, negativeStreak >= confirmMisses {
                lastDetected = nil
                onMeetingEnded?(ended)
            }
        }
    }

    private func pruneDismissalsAgainstRunningApps() {
        let running = NSWorkspace.shared.runningApplications
        let currentMeetingBundles = Set(
            running.compactMap { app -> String? in
                guard let bid = app.bundleIdentifier else { return nil }
                if knownApps.contains(where: { $0.bundleID == bid }) { return bid }
                return nil
            }
        )

        // If a dismissed meeting app family fully quit, allow prompts next launch.
        for bid in dismissedBundleIDs where !currentMeetingBundles.contains(bid) {
            let family = Self.appFamily(for: bid, appName: nil)
            let familyStillRunning = Self.bundleIDs(inFamily: family)
                .contains(where: { currentMeetingBundles.contains($0) })
            if !familyStillRunning {
                dismissedBundleIDs.remove(bid)
            }
        }

        let now = Date()
        for (family, until) in snoozedFamiliesUntil where until <= now {
            snoozedFamiliesUntil.removeValue(forKey: family)
            // Allow a later call in the same app; keep fingerprints so the same
            // dismissed session doesn't immediately return.
            for bid in Self.bundleIDs(inFamily: family) {
                dismissedBundleIDs.remove(bid)
            }
        }

        if currentMeetingBundles.isEmpty {
            dismissedFingerprints.removeAll()
            dismissedBundleIDs.removeAll()
        }
    }

    private func isSuppressed(_ meeting: DetectedMeeting) -> Bool {
        if dismissedFingerprints.contains(meeting.fingerprint) { return true }
        if dismissedBundleIDs.contains(meeting.bundleID) { return true }
        let family = Self.appFamily(for: meeting.bundleID, appName: meeting.appName)
        if let until = snoozedFamiliesUntil[family], until > Date() { return true }
        return false
    }

    private func detectMeeting(from running: [NSRunningApplication]) -> DetectedMeeting? {
        let windowInfo = Self.onScreenWindowInfo()

        // Only strong "in a call" signals — never "app is merely open / frontmost".
        if let hit = detectFromWindows(windowInfo) {
            return hit
        }

        // FaceTime is call-first; a visible FaceTime window is enough.
        for app in running {
            guard let bid = app.bundleIdentifier,
                  bid == "com.apple.FaceTime"
            else { continue }
            let titles = windowInfo.filter { $0.ownerPID == app.processIdentifier }.map(\.title)
            if titles.contains(where: { !$0.isEmpty }) {
                return DetectedMeeting(
                    appName: "FaceTime",
                    bundleID: bid,
                    detail: titles.first(where: { !$0.isEmpty }) ?? "FaceTime"
                )
            }
        }

        return nil
    }

    private func detectFromWindows(_ windows: [WindowInfo]) -> DetectedMeeting? {
        for window in windows {
            let title = window.title
            guard !title.isEmpty else { continue }

            if Self.meetsBrowserMeet(title),
               let bid = bundleID(forPID: window.ownerPID),
               browserBundleIDs.contains(bid)
            {
                return DetectedMeeting(appName: "Google Meet", bundleID: bid, detail: title)
            }
            if title.localizedCaseInsensitiveContains("Zoom Meeting")
                || title.localizedCaseInsensitiveContains("Zoom Webinar")
            {
                return DetectedMeeting(
                    appName: "Zoom",
                    bundleID: bundleID(forPID: window.ownerPID) ?? "us.zoom.xos",
                    detail: title
                )
            }
            if Self.looksLikeTeamsCallTitle(title) {
                return DetectedMeeting(
                    appName: "Teams",
                    bundleID: bundleID(forPID: window.ownerPID) ?? "com.microsoft.teams2",
                    detail: title
                )
            }
            if title.localizedCaseInsensitiveContains("Webex")
                && title.localizedCaseInsensitiveContains("Meeting")
            {
                return DetectedMeeting(
                    appName: "Webex",
                    bundleID: bundleID(forPID: window.ownerPID) ?? "com.webex.meetingmanager",
                    detail: title
                )
            }
            if title.localizedCaseInsensitiveContains("huddle")
                && (bundleID(forPID: window.ownerPID)?.contains("slack") == true)
            {
                return DetectedMeeting(
                    appName: "Slack",
                    bundleID: bundleID(forPID: window.ownerPID) ?? "com.tinyspeck.slackmacgap",
                    detail: "Huddle in progress"
                )
            }
            if title.localizedCaseInsensitiveContains("voice channel")
                || (title.localizedCaseInsensitiveContains("discord")
                    && title.localizedCaseInsensitiveContains("call"))
            {
                if bundleID(forPID: window.ownerPID)?.contains("Discord") == true {
                    return DetectedMeeting(
                        appName: "Discord",
                        bundleID: bundleID(forPID: window.ownerPID) ?? "com.hnc.Discord",
                        detail: title
                    )
                }
            }
        }
        return nil
    }

    /// Teams chat/channel/calendar titles all end in "| Microsoft Teams" — that alone
    /// is not a meeting. Only match call-specific title wording.
    private static func looksLikeTeamsCallTitle(_ title: String) -> Bool {
        if isTeamsNonCallChrome(title) { return false }

        let lower = title.lowercased()
        // "Meeting with Alex | Microsoft Teams", "Call with Alex | …"
        if lower.contains("meeting with") || lower.contains("call with") {
            return true
        }
        // Native call chrome (avoid bare "meeting" — channel names use that often).
        if lower.contains("call in progress")
            || lower.contains("ongoing call")
            || lower.contains("teams call")
            || lower.contains("| meeting |")
        {
            return true
        }
        return false
    }

    private static func isTeamsNonCallChrome(_ title: String) -> Bool {
        let lower = title.lowercased()
        if lower.contains("chat |") || lower.contains("| chat") { return true }
        if lower.range(of: #"\(\d+\)\s*chat"#, options: .regularExpression) != nil { return true }
        if lower.contains("calendar") { return true }
        if lower.contains("activity |") || lower.hasPrefix("activity") { return true }
        if lower.contains("teams and channels") { return true }
        return false
    }

    private static func meetsBrowserMeet(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("meet.google.com")
            || lower.hasPrefix("meet -")
            || lower.contains("google meet")
            || lower.contains(" · meet")
    }

    private static func appFamily(for bundleID: String, appName: String?) -> String {
        if let appName, !appName.isEmpty { return appName.lowercased() }
        if bundleID.contains("teams") { return "teams" }
        if bundleID.contains("zoom") { return "zoom" }
        if bundleID.contains("webex") { return "webex" }
        if bundleID.contains("FaceTime") { return "facetime" }
        if bundleID.contains("slack") { return "slack" }
        if bundleID.contains("Discord") { return "discord" }
        return bundleID
    }

    private static func bundleIDs(inFamily family: String) -> [String] {
        switch family.lowercased() {
        case "teams":
            return ["com.microsoft.teams2", "com.microsoft.teams", "com.microsoft.teams.mac"]
        case "zoom":
            return ["us.zoom.xos", "zoom.us"]
        case "webex":
            return ["com.cisco.webexmeetingsapp", "com.webex.meetingmanager"]
        case "facetime":
            return ["com.apple.FaceTime"]
        case "slack":
            return ["com.tinyspeck.slackmacgap"]
        case "discord":
            return ["com.hnc.Discord"]
        default:
            return []
        }
    }

    private func bundleID(forPID pid: pid_t) -> String? {
        NSWorkspace.shared.runningApplications.first(where: { $0.processIdentifier == pid })?.bundleIdentifier
    }

    private struct WindowInfo {
        let title: String
        let ownerPID: pid_t
    }

    private static func onScreenWindowInfo() -> [WindowInfo] {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else {
            return []
        }

        return list.compactMap { info in
            let title = info[kCGWindowName as String] as? String ?? ""
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard pid != 0 else { return nil }
            // Layer 0 is normal windows; skip menu bar / overlays.
            if let layer = info[kCGWindowLayer as String] as? Int, layer != 0 {
                return nil
            }
            return WindowInfo(title: title, ownerPID: pid)
        }
    }
}

import AppKit
import Foundation

struct DetectedMeeting: Equatable, Sendable {
    let appName: String
    let bundleID: String
    let detail: String
}

/// Watches for Zoom / Teams / Meet / Webex / FaceTime and surfaces a prompt
/// when a meeting appears to be in progress — Wispr-style "meeting recognized".
@MainActor
final class MeetingDetector {
    var onMeetingDetected: ((DetectedMeeting) -> Void)?
    var onMeetingEnded: (() -> Void)?

    private var timer: Timer?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var lastDetected: DetectedMeeting?
    /// Bundle IDs the user dismissed until that app quits (or detector restarts).
    private var dismissedBundleIDs: Set<String> = []
    private var runningMeetingBundleIDs: Set<String> = []

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
        if let lastDetected {
            dismissedBundleIDs.insert(lastDetected.bundleID)
        }
        lastDetected = nil
        onMeetingEnded?()
    }

    func clearDismissal(for bundleID: String) {
        dismissedBundleIDs.remove(bundleID)
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
        let running = NSWorkspace.shared.runningApplications
        let currentMeetingBundles = Set(
            running.compactMap { app -> String? in
                guard let bid = app.bundleIdentifier else { return nil }
                if knownApps.contains(where: { $0.bundleID == bid }) { return bid }
                return nil
            }
        )

        // If a dismissed meeting app quit, allow prompts again next time.
        for bid in dismissedBundleIDs where !currentMeetingBundles.contains(bid) {
            dismissedBundleIDs.remove(bid)
        }
        runningMeetingBundleIDs = currentMeetingBundles

        if let detected = detectMeeting(from: running) {
            if dismissedBundleIDs.contains(detected.bundleID) {
                return
            }
            if detected != lastDetected {
                lastDetected = detected
                onMeetingDetected?(detected)
            }
        } else if lastDetected != nil {
            lastDetected = nil
            onMeetingEnded?()
        }
    }

    private func detectMeeting(from running: [NSRunningApplication]) -> DetectedMeeting? {
        let windowInfo = Self.onScreenWindowInfo()

        // Prefer strong "in a call" signals from window titles.
        if let hit = detectFromWindows(windowInfo) {
            return hit
        }

        // Native meeting apps that are frontmost — likely in/joining a call.
        if let front = NSWorkspace.shared.frontmostApplication,
           let bid = front.bundleIdentifier,
           let known = knownApps.first(where: { $0.bundleID == bid })
        {
            // Slack/Discord only when window title looks like a huddle/call.
            if bid.contains("slack") || bid.contains("Discord") {
                return nil
            }
            return DetectedMeeting(
                appName: known.name,
                bundleID: bid,
                detail: "\(known.name) is active"
            )
        }

        // Meeting app running with an on-screen call-like window.
        for app in running {
            guard let bid = app.bundleIdentifier,
                  let known = knownApps.first(where: { $0.bundleID == bid }),
                  !bid.contains("slack"),
                  !bid.contains("Discord")
            else { continue }

            let titles = windowInfo.filter { $0.ownerPID == app.processIdentifier }.map(\.title)
            if titles.contains(where: { Self.looksLikeCallTitle($0, appName: known.name) }) {
                return DetectedMeeting(
                    appName: known.name,
                    bundleID: bid,
                    detail: "Call window detected"
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
            if title.localizedCaseInsensitiveContains("| Microsoft Teams")
                || title.localizedCaseInsensitiveContains("Meeting with")
                   && title.localizedCaseInsensitiveContains("Teams")
            {
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
        }
        return nil
    }

    private static func meetsBrowserMeet(_ title: String) -> Bool {
        let lower = title.lowercased()
        return lower.contains("meet.google.com")
            || lower.hasPrefix("meet -")
            || lower.contains("google meet")
            || lower.contains(" · meet")
    }

    private static func looksLikeCallTitle(_ title: String, appName: String) -> Bool {
        let lower = title.lowercased()
        if lower.contains("meeting") || lower.contains("call") || lower.contains("webinar") {
            return true
        }
        if appName == "Zoom" && (lower.contains("zoom") && title.count > 4) {
            return lower.contains("zoom meeting") || lower.contains("zoom webinar")
        }
        return false
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

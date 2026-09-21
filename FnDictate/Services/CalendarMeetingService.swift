import AppKit
import EventKit
import Foundation
import Observation

struct CalendarMeetingContext: Equatable, Sendable {
    let eventIdentifier: String
    let title: String
    let startDate: Date
    let endDate: Date
    let attendees: [String]
    let location: String?
    let notes: String?

    /// Wispr-style 1:1 shortcut: exactly one remote person we can name onto Others.
    /// Calendar often lists only the other party; when two names appear we cannot
    /// reliably know which is "You" without account identity, so we stay conservative.
    var remoteOneOnOneName: String? {
        let cleaned = attendees
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .uniqued()
        if cleaned.count == 1 {
            return cleaned[0]
        }
        return nil
    }
}

/// Looks up the Calendar event overlapping "now" (or next soon) for speaker names + briefs.
@MainActor
@Observable
final class CalendarMeetingService {
    var authorizationStatus: EKAuthorizationStatus = .notDetermined

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .fullAccess:
            return true
        case .authorized:
            // Legacy status from older OS / SDK mappings.
            return true
        default:
            return false
        }
    }

    /// Already denied/restricted — must change in System Settings (re-prompt never shows).
    var needsOpenSettings: Bool {
        switch authorizationStatus {
        case .denied, .restricted:
            return true
        default:
            return false
        }
    }

    private let store = EKEventStore()

    init() {
        refreshStatus()
    }

    func refreshStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    @discardableResult
    func requestAccess() async -> Bool {
        refreshStatus()
        if isAuthorized { return true }
        // Denied/restricted: calling request again never shows UI — open Settings instead.
        if needsOpenSettings {
            return false
        }
        do {
            let granted = try await store.requestFullAccessToEvents()
            refreshStatus()
            if granted || isAuthorized {
                // Store may have been created before grant; reset so fetches see calendars.
                store.reset()
            }
            return granted || isAuthorized
        } catch {
            refreshStatus()
            return isAuthorized
        }
    }

    func openCalendarSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Calendars",
        ]
        for string in candidates {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    /// Prefer an event covering now; otherwise the next event starting within `lookahead`.
    func currentOrUpcoming(lookahead: TimeInterval = 30 * 60) -> CalendarMeetingContext? {
        refreshStatus()
        guard isAuthorized else { return nil }

        let now = Date()
        let windowEnd = now.addingTimeInterval(lookahead)
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-15 * 60),
            end: windowEnd,
            calendars: nil
        )
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }

        let covering = events.first { $0.startDate <= now && $0.endDate >= now }
        let upcoming = events.first { $0.startDate > now }
        guard let event = covering ?? upcoming else { return nil }
        return context(from: event)
    }

    private func context(from event: EKEvent) -> CalendarMeetingContext {
        let names = (event.attendees ?? [])
            .compactMap { attendee -> String? in
                let name = attendee.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let name, !name.isEmpty { return name }
                let url = attendee.url.absoluteString
                if url.contains("@") {
                    return url.replacingOccurrences(of: "mailto:", with: "")
                }
                return nil
            }
            .uniqued()

        return CalendarMeetingContext(
            eventIdentifier: event.eventIdentifier ?? UUID().uuidString,
            title: event.title ?? "Untitled event",
            startDate: event.startDate,
            endDate: event.endDate,
            attendees: names,
            location: event.location,
            notes: event.notes
        )
    }
}

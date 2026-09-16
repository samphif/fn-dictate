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
}

/// Looks up the Calendar event overlapping "now" (or next soon) for speaker names + briefs.
@MainActor
@Observable
final class CalendarMeetingService {
    var authorizationStatus: EKAuthorizationStatus = .notDetermined
    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    private let store = EKEventStore()

    func refreshStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    @discardableResult
    func requestAccess() async -> Bool {
        refreshStatus()
        if isAuthorized { return true }
        do {
            let granted = try await store.requestFullAccessToEvents()
            refreshStatus()
            return granted
        } catch {
            refreshStatus()
            return false
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

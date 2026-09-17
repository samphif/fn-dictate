import EventKit
import Foundation
import Observation

struct ReminderListInfo: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
}

enum RemindersServiceError: LocalizedError {
    case notAuthorized
    case noWritableLists
    case listNotFound
    case emptyItems
    case saveFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Reminders access is required. Allow it in System Settings → Privacy & Security → Reminders."
        case .noWritableLists:
            return "No writable Reminders lists were found."
        case .listNotFound:
            return "That Reminders list is no longer available."
        case .emptyItems:
            return "No action items to send."
        case .saveFailed(let message):
            return message
        }
    }
}

/// Creates Apple Reminders from meeting action items (manual export).
@MainActor
@Observable
final class RemindersService {
    var authorizationStatus: EKAuthorizationStatus = .notDetermined
    var lists: [ReminderListInfo] = []
    /// Last list the user picked; restored when available.
    var preferredListID: String? {
        didSet {
            if preferredListID != oldValue {
                UserDefaults.standard.set(preferredListID, forKey: preferredListKey)
            }
        }
    }

    var isAuthorized: Bool {
        authorizationStatus == .fullAccess
    }

    private let store = EKEventStore()
    private let preferredListKey = "FnDictate.remindersPreferredListID"

    init() {
        preferredListID = UserDefaults.standard.string(forKey: preferredListKey)
        refreshStatus()
        if isAuthorized {
            reloadLists()
        }
    }

    func refreshStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        if !isAuthorized {
            lists = []
        }
    }

    @discardableResult
    func requestAccess() async -> Bool {
        refreshStatus()
        if isAuthorized {
            reloadLists()
            return true
        }
        do {
            let granted = try await store.requestFullAccessToReminders()
            refreshStatus()
            if granted { reloadLists() }
            return granted
        } catch {
            refreshStatus()
            return false
        }
    }

    func reloadLists() {
        guard isAuthorized else {
            lists = []
            return
        }
        lists = store.calendars(for: .reminder)
            .filter(\.allowsContentModifications)
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .map { ReminderListInfo(id: $0.calendarIdentifier, title: $0.title) }
    }

    /// Preferred writable list, falling back to the system default, then the first list.
    func resolvedListID(preferred: String? = nil) -> String? {
        let want = preferred ?? preferredListID
        if let want, lists.contains(where: { $0.id == want }) {
            return want
        }
        if let defaultID = store.defaultCalendarForNewReminders()?.calendarIdentifier,
           lists.contains(where: { $0.id == defaultID })
        {
            return defaultID
        }
        return lists.first?.id
    }

    /// Adds one Reminder per action item into the chosen list.
    @discardableResult
    func addActionItems(
        _ items: [String],
        toListID listID: String,
        meetingTitle: String
    ) throws -> Int {
        refreshStatus()
        guard isAuthorized else { throw RemindersServiceError.notAuthorized }

        let trimmed = items
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { throw RemindersServiceError.emptyItems }

        guard let calendar = store.calendars(for: .reminder)
            .first(where: { $0.calendarIdentifier == listID && $0.allowsContentModifications })
        else {
            throw RemindersServiceError.listNotFound
        }

        do {
            for title in trimmed {
                let reminder = EKReminder(eventStore: store)
                reminder.calendar = calendar
                reminder.title = title
                reminder.notes = "From Fn Dictate · \(meetingTitle)"
                try store.save(reminder, commit: false)
            }
            try store.commit()
            preferredListID = listID
            return trimmed.count
        } catch {
            store.reset()
            throw RemindersServiceError.saveFailed(error.localizedDescription)
        }
    }
}

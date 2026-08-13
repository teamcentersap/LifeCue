import Foundation
import EventKit

/// Production Calendar implementation backed by EventKit.
/// Calendar access is read-only and requested only when the user explicitly enters the Calendar feature.
@MainActor
final class EventKitCalendarService: CalendarServing {
    private let store: EKEventStore

    init(store: EKEventStore = EKEventStore()) {
        self.store = store
    }

    func authorizationStatus() async -> CalendarAuthorizationStatus {
        Self.mapAuthorization(EKEventStore.authorizationStatus(for: .event))
    }

    /// Maps EventKit status into LifeCue’s model. Full read access is required for Calendar.
    /// `.writeOnly` is not full access → same “not usable” path as before (`@unknown default`).
    nonisolated static func mapAuthorization(_ ekStatus: EKAuthorizationStatus) -> CalendarAuthorizationStatus {
        switch ekStatus {
        case .notDetermined: return .notDetermined
        case .fullAccess: return .fullAccess
        case .denied: return .denied
        case .restricted: return .restricted
        case .writeOnly: return .unavailable
        @unknown default: return .unavailable
        }
    }

    func requestFullAccessToEvents() async -> CalendarAuthorizationStatus {
        // iOS 17+: full-access API.
        // No repeated requests: callers should guard on `notDetermined`.
        await withCheckedContinuation { (continuation: CheckedContinuation<CalendarAuthorizationStatus, Never>) in
            store.requestFullAccessToEvents { granted, _ in
                continuation.resume(returning: granted ? .fullAccess : .denied)
            }
        }
    }

    func fetchEvents(
        from: Date,
        to: Date,
        calendarIdentifiers: [String]?
    ) async throws -> [CalendarEvent] {
        let calendars = try resolveCalendars(calendarIdentifiers: calendarIdentifiers)
        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: calendars)
        let ekEvents = store.events(matching: predicate)

        return ekEvents
            .map { ekEvent in
                let tz = ekEvent.timeZone
                return CalendarEvent(
                    id: ekEvent.eventIdentifier,
                    title: ekEvent.title ?? "",
                    startDate: ekEvent.startDate,
                    endDate: ekEvent.isAllDay ? ekEvent.startDate : ekEvent.endDate,
                    isAllDay: ekEvent.isAllDay,
                    calendarName: ekEvent.calendar.title,
                    calendarIdentifier: ekEvent.calendar.calendarIdentifier,
                    timeZoneIdentifier: tz?.identifier ?? TimeZone.current.identifier
                )
            }
            .sorted { $0.startDate < $1.startDate }
    }

    func fetchAvailableCalendars() async throws -> [CalendarSource] {
        let cals = store.calendars(for: .event)
        // Keep only user-visible calendars.
        return cals
            .filter { $0.allowsContentModifications == false || $0.title != "" }
            .map { CalendarSource(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title < $1.title }
    }

    private func resolveCalendars(calendarIdentifiers: [String]?) throws -> [EKCalendar] {
        let all = store.calendars(for: .event)
        guard let calendarIdentifiers, !calendarIdentifiers.isEmpty else { return all }
        let selected = all.filter { calendarIdentifiers.contains($0.calendarIdentifier) }
        return selected.isEmpty ? all : selected
    }
}


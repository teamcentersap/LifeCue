import Foundation

/// Deterministic, dependency-injected test double for Calendar.
final class FakeCalendarService: CalendarServing {
    var status: CalendarAuthorizationStatus
    var shouldFailFetch = false
    var availableCalendars: [CalendarSource]
    var events: [CalendarEvent]
    /// Test observation: how many times full access was requested.
    private(set) var requestAccessCallCount = 0

    init(
        status: CalendarAuthorizationStatus = .notDetermined,
        availableCalendars: [CalendarSource] = [CalendarSource(id: "all", title: "All Calendars")],
        events: [CalendarEvent] = []
    ) {
        self.status = status
        self.availableCalendars = availableCalendars
        self.events = events
    }

    func authorizationStatus() async -> CalendarAuthorizationStatus {
        status
    }

    func requestFullAccessToEvents() async -> CalendarAuthorizationStatus {
        requestAccessCallCount += 1
        // In tests we treat "request" as transitioning to fullAccess.
        if status == .notDetermined {
            status = .fullAccess
        }
        return status
    }

    func fetchEvents(
        from: Date,
        to: Date,
        calendarIdentifiers: [String]? = nil
    ) async throws -> [CalendarEvent] {
        if shouldFailFetch { throw NSError(domain: "FakeCalendarService", code: 1) }

        let filteredByRange = events.filter { event in
            // Include if overlaps the [from, to] interval.
            event.startDate <= to && event.endDate >= from
        }

        guard let calendarIdentifiers else { return filteredByRange.sorted { $0.startDate < $1.startDate } }
        return filteredByRange
            .filter { event in
                if let cid = event.calendarIdentifier, calendarIdentifiers.contains(cid) { return true }
                return calendarIdentifiers.contains(event.calendarName)
            }
            .sorted { $0.startDate < $1.startDate }
    }

    func fetchAvailableCalendars() async throws -> [CalendarSource] {
        availableCalendars
    }
}


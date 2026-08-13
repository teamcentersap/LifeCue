import XCTest
@testable import LifeCue

final class CalendarServiceTests: XCTestCase {
    private func makeEvent(
        id: String = "e1",
        title: String = "Event",
        isAllDay: Bool = false,
        calendarName: String = "Work",
        calendarIdentifier: String? = "cal1",
        timeZoneIdentifier: String,
        start: Date,
        end: Date
    ) -> CalendarEvent {
        CalendarEvent(
            id: id,
            title: title,
            startDate: start,
            endDate: end,
            isAllDay: isAllDay,
            calendarName: calendarName,
            calendarIdentifier: calendarIdentifier,
            timeZoneIdentifier: timeZoneIdentifier
        )
    }

    func testAuthorizationNotDeterminedTransitionsOnRequest() async {
        let svc = FakeCalendarService(status: .notDetermined)
        let status1 = await svc.authorizationStatus()
        XCTAssertEqual(status1, .notDetermined)
        let newStatus = await svc.requestFullAccessToEvents()
        XCTAssertEqual(newStatus, .fullAccess)
        let status2 = await svc.authorizationStatus()
        XCTAssertEqual(status2, .fullAccess)
    }

    func testWriteOnlyEventKitStatusMapsToUnavailable() {
        // Write-only ≠ full read access; Calendar features must not treat it as usable.
        XCTAssertEqual(
            EventKitCalendarService.mapAuthorization(.writeOnly),
            .unavailable
        )
        XCTAssertNotEqual(
            EventKitCalendarService.mapAuthorization(.writeOnly),
            .fullAccess
        )
    }

    func testEmptyCalendarReturnsEmpty() async throws {
        let svc = FakeCalendarService(status: .fullAccess, events: [])
        let start = Date()
        let end = start.addingTimeInterval(3600)
        let events = try await svc.fetchEvents(from: start, to: end, calendarIdentifiers: nil as [String]?)
        XCTAssertTrue(events.isEmpty)
    }

    func testDateRangeFiltersEventsByOverlap() async throws {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tokyo

        let aStart = cal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 10, minute: 0))!
        let aEnd = cal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 11, minute: 0))!

        let bStart = cal.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 10, minute: 0))!
        let bEnd = cal.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 11, minute: 0))!

        let eA = makeEvent(timeZoneIdentifier: tokyo.identifier, start: aStart, end: aEnd)
        let eB = makeEvent(
            id: "eB",
            calendarName: "Work2",
            calendarIdentifier: "cal2",
            timeZoneIdentifier: tokyo.identifier,
            start: bStart,
            end: bEnd
        )

        let svc = FakeCalendarService(status: .fullAccess, availableCalendars: [], events: [eA, eB])

        let from = aStart.addingTimeInterval(-60)
        let to = aEnd.addingTimeInterval(60)
        let events = try await svc.fetchEvents(from: from, to: to, calendarIdentifiers: nil as [String]?)
        XCTAssertEqual(events.map(\.id), ["e1"])
    }

    func testServiceFailureThrows() async {
        let svc = FakeCalendarService(status: .fullAccess, events: [])
        svc.shouldFailFetch = true
        do {
            _ = try await svc.fetchEvents(from: Date(), to: Date().addingTimeInterval(10), calendarIdentifiers: nil as [String]?)
            XCTFail("Expected fetchEvents to throw")
        } catch {
            // expected
        }
    }

    func testPrefillAllDayUsesEventDayAndExcludesTime() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tokyo

        let start = cal.startOfDay(for: cal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9, minute: 0))!)
        let end = start

        let event = makeEvent(isAllDay: true, timeZoneIdentifier: tokyo.identifier, start: start, end: end)
        let pre = CalendarEventPrefill.makePrefill(from: event)

        XCTAssertEqual(pre.title, event.title)
        XCTAssertEqual(pre.includeTime, false)
        XCTAssertEqual(pre.reminderTimeZoneIdentifier, tokyo.identifier)

        let day = Calendar(identifier: .gregorian).day(from: pre.eventDate, in: tokyo)
        XCTAssertEqual(day, 10)
    }

    func testPrefillTimedPreservesWallClockHourMinuteInEventTimeZone() {
        let la = TimeZone(identifier: "America/Los_Angeles")!
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = la

        let start = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 14, minute: 30))!
        let end = cal.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 15, minute: 30))!

        let event = makeEvent(timeZoneIdentifier: la.identifier, start: start, end: end)
        let pre = CalendarEventPrefill.makePrefill(from: event)

        XCTAssertTrue(pre.includeTime)
        let comps = cal.dateComponents([.hour, .minute], from: pre.eventTime)
        XCTAssertEqual(comps.hour, 14)
        XCTAssertEqual(comps.minute, 30)
    }
}

private extension Calendar {
    func day(from date: Date, in tz: TimeZone) -> Int {
        var c = self
        c.timeZone = tz
        return c.component(.day, from: date)
    }
}


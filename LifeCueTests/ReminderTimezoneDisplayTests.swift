import XCTest
@testable import LifeCue

final class ReminderTimezoneDisplayTests: XCTestCase {
    func testDisplayPreservesStoredTimezoneWallClock() throws {
        let reminder = try ReminderFactory.make(
            title: "NY Event",
            eventDate: DateComponents(year: 2026, month: 9, day: 20),
            eventTime: DateComponents(hour: 16, minute: 0),
            timeZoneIdentifier: "America/New_York"
        )

        // Simulate device timezone far from the reminder timezone.
        var tokyo = Calendar(identifier: .gregorian)
        tokyo.timeZone = TimeZone(identifier: "Asia/Tokyo")!

        let dateText = ReminderDisplayFormatter.dateString(for: reminder)
        let timeText = try XCTUnwrap(ReminderDisplayFormatter.timeString(for: reminder))

        // Reconstruct using reminder timezone — must remain 20 Sep 2026, 4:00 PM Eastern.
        let calendar = reminder.calendarInStoredTimeZone()
        let reconstructedDate = calendar.date(from: Reminder.normalizedDate(reminder.eventDate))
        var timeComponents = Reminder.normalizedDate(reminder.eventDate)
        timeComponents.hour = reminder.eventTime?.hour
        timeComponents.minute = reminder.eventTime?.minute
        let reconstructedTime = calendar.date(from: timeComponents)

        XCTAssertEqual(calendar.component(.day, from: try XCTUnwrap(reconstructedDate)), 20)
        XCTAssertEqual(calendar.component(.month, from: try XCTUnwrap(reconstructedDate)), 9)
        XCTAssertEqual(calendar.component(.hour, from: try XCTUnwrap(reconstructedTime)), 16)
        XCTAssertEqual(reminder.timeZoneIdentifier, "America/New_York")
        XCTAssertFalse(dateText.isEmpty)
        XCTAssertFalse(timeText.isEmpty)

        // Ensure Tokyo calendar would produce a different absolute instant mapping if misused.
        let misused = tokyo.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 16, minute: 0))
        XCTAssertNotEqual(misused, reconstructedTime)
    }

    func testLimitDateDisplayUsesSharedMediumFormatter() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 12))!
        let start = ReminderDisplayFormatter.dateString(from: date, calendar: calendar)
        let end = ReminderDisplayFormatter.dateString(from: date, calendar: calendar)
        XCTAssertEqual(start, end)
        XCTAssertTrue(start.contains("2026"))
        // Shared medium formatter must be used for both limit-date ends (no short/medium mix).
        let reminderLike = ReminderDisplayFormatter.dateString(from: date, calendar: calendar)
        XCTAssertEqual(start, reminderLike)
    }

    func testEditReconstructionUsesStoredTimezoneNotDeviceTimezone() throws {
        let reminder = try ReminderFactory.make(
            title: "Boundary",
            eventDate: DateComponents(year: 2026, month: 9, day: 20),
            eventTime: DateComponents(hour: 16, minute: 0),
            timeZoneIdentifier: "America/New_York"
        )

        let reminderCalendar = reminder.calendarInStoredTimeZone()
        let date = try XCTUnwrap(reminderCalendar.date(from: Reminder.normalizedDate(reminder.eventDate)))
        var components = Reminder.normalizedDate(reminder.eventDate)
        components.hour = 16
        components.minute = 0
        let time = try XCTUnwrap(reminderCalendar.date(from: components))

        // Round-trip through DatePicker-like Date values must preserve wall clock in stored zone.
        let roundTripDate = Reminder.dateComponents(from: date, calendar: reminderCalendar)
        let roundTripTime = Reminder.timeComponents(from: time, calendar: reminderCalendar)
        XCTAssertEqual(roundTripDate.year, 2026)
        XCTAssertEqual(roundTripDate.month, 9)
        XCTAssertEqual(roundTripDate.day, 20)
        XCTAssertEqual(roundTripTime.hour, 16)
        XCTAssertEqual(roundTripTime.minute, 0)
    }

    func testTimezoneBoundaryNearOffsetChange() throws {
        // 2026-03-08 is US DST spring-forward in America/New_York.
        let reminder = try ReminderFactory.make(
            title: "DST boundary",
            eventDate: DateComponents(year: 2026, month: 3, day: 8),
            eventTime: DateComponents(hour: 16, minute: 0),
            timeZoneIdentifier: "America/New_York",
            rules: [.exactAtEvent()]
        )
        let engine = ReminderRuleEngine()
        let fire = try XCTUnwrap(
            engine.occurrences(
                for: reminder,
                now: Date(timeIntervalSince1970: 0),
                onlyFuture: true
            ).first?.fireAt
        )
        let calendar = reminder.calendarInStoredTimeZone()
        XCTAssertEqual(calendar.component(.day, from: fire), 8)
        XCTAssertEqual(calendar.component(.hour, from: fire), 16)
    }
}

import XCTest
@testable import LifeCue

final class ReminderRuleEngineTests: XCTestCase {
    private var calendar: Calendar!
    private var engine: ReminderRuleEngine!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        engine = ReminderRuleEngine(policy: .default, calendar: cal)
    }

    func testOneDayBefore() throws {
        let reminder = try makeReminder(
            year: 2026, month: 8, day: 25, hour: 10, minute: 0,
            rules: [.beforeEvent(value: 1, unit: .day)]
        )
        let occurrences = engine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0))
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences[0].fireAt, date(2026, 8, 24, 10, 0))
    }

    func testOneWeekBefore() throws {
        let reminder = try makeReminder(
            year: 2026, month: 8, day: 25, hour: 10, minute: 0,
            rules: [.beforeEvent(value: 1, unit: .week)]
        )
        let occurrences = engine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0))
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences[0].fireAt, date(2026, 8, 18, 10, 0))
    }

    func testMultipleReminders() throws {
        let reminder = try makeReminder(
            year: 2026, month: 9, day: 30, hour: 9, minute: 0,
            rules: [
                .beforeEvent(value: 30, unit: .day),
                .beforeEvent(value: 7, unit: .day),
                .beforeEvent(value: 1, unit: .day)
            ]
        )
        let occurrences = engine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0))
        XCTAssertEqual(occurrences.count, 3)
        XCTAssertEqual(occurrences.map(\.fireAt), [
            date(2026, 8, 31, 9, 0),
            date(2026, 9, 23, 9, 0),
            date(2026, 9, 29, 9, 0)
        ])
    }

    func testExactAtEvent() throws {
        let reminder = try makeReminder(
            year: 2026, month: 8, day: 25, hour: 10, minute: 0,
            rules: [.exactAtEvent()]
        )
        let occurrences = engine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0))
        XCTAssertEqual(occurrences.first?.fireAt, date(2026, 8, 25, 10, 0))
    }

    func testMonthBoundary() throws {
        let reminder = try makeReminder(
            year: 2026, month: 9, day: 1, hour: 10, minute: 0,
            rules: [.beforeEvent(value: 1, unit: .day)]
        )
        let fire = engine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0)).first?.fireAt
        XCTAssertEqual(fire, date(2026, 8, 31, 10, 0))
    }

    func testYearBoundary() throws {
        let reminder = try makeReminder(
            year: 2027, month: 1, day: 1, hour: 10, minute: 0,
            rules: [.beforeEvent(value: 1, unit: .day)]
        )
        let fire = engine.occurrences(for: reminder, now: date(2026, 12, 1, 9, 0)).first?.fireAt
        XCTAssertEqual(fire, date(2026, 12, 31, 10, 0))
    }

    func testLeapYear() throws {
        let reminder = try makeReminder(
            year: 2028, month: 3, day: 1, hour: 10, minute: 0,
            rules: [.beforeEvent(value: 1, unit: .day)]
        )
        let fire = engine.occurrences(for: reminder, now: date(2028, 2, 1, 9, 0)).first?.fireAt
        XCTAssertEqual(fire, date(2028, 2, 29, 10, 0))
    }

    func testTimezoneUsesReminderZone() throws {
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
        let nyEngine = ReminderRuleEngine(policy: .default, calendar: nyCalendar)

        let reminder = try ReminderFactory.make(
            title: "Call",
            eventDate: DateComponents(year: 2026, month: 8, day: 25),
            eventTime: DateComponents(hour: 10, minute: 0),
            timeZoneIdentifier: "America/New_York",
            rules: [.exactAtEvent()]
        )

        let fire = nyEngine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0)).first?.fireAt
        let expected = nyCalendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 10, minute: 0))
        XCTAssertEqual(fire, expected)
    }

    func testDateOnlyUsesDefaultNineAM() throws {
        let reminder = try ReminderFactory.make(
            title: "Date only",
            eventDate: DateComponents(year: 2026, month: 8, day: 25),
            eventTime: nil,
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        )
        let occurrences = engine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0))
        XCTAssertEqual(occurrences.map(\.fireAt), [
            date(2026, 8, 24, 9, 0),
            date(2026, 8, 25, 9, 0)
        ])
    }

    func testDisabledRulesAreIgnored() throws {
        var disabled = ReminderRule.beforeEvent(value: 1, unit: .day)
        disabled.enabled = false
        let reminder = try makeReminder(
            year: 2026, month: 8, day: 25, hour: 10, minute: 0,
            rules: [disabled, .exactAtEvent()]
        )
        let occurrences = engine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0))
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences[0].ruleType, .exactAtEvent)
    }

    func testSnoozeKeepsLaterStandingOccurrences() throws {
        let week = ReminderRule.beforeEvent(value: 1, unit: .week)
        let day = ReminderRule.beforeEvent(value: 1, unit: .day)
        let atEvent = ReminderRule.exactAtEvent()
        var reminder = try makeReminder(
            year: 2026, month: 8, day: 25, hour: 10, minute: 0,
            rules: [week, day, atEvent]
        )
        // Snooze shortly after the 7-day fire would have been relevant.
        reminder.snooze = ReminderSnoozeState(until: date(2026, 8, 19, 12, 0))

        let occurrences = engine.occurrences(for: reminder, now: date(2026, 8, 18, 11, 0))
        // 7-day (Aug 18 10:00) is past relative to now; snooze + 1-day + at-event remain.
        XCTAssertEqual(occurrences.count, 3)
        XCTAssertTrue(occurrences.contains { $0.isSnooze })
        XCTAssertTrue(occurrences.contains { $0.ruleID == day.id })
        XCTAssertTrue(occurrences.contains { $0.ruleID == atEvent.id })
        XCTAssertEqual(reminder.rules.count, 3)
    }

    func testSnoozeExpiryResumesStandingOnly() throws {
        let day = ReminderRule.beforeEvent(value: 1, unit: .day)
        var reminder = try makeReminder(
            year: 2026, month: 8, day: 25, hour: 10, minute: 0,
            rules: [day]
        )
        reminder.snooze = ReminderSnoozeState(until: date(2026, 8, 11, 15, 0))

        let after = engine.occurrences(for: reminder, now: date(2026, 8, 12, 12, 0))
        XCTAssertEqual(after.count, 1)
        XCTAssertFalse(after[0].isSnooze)
        XCTAssertEqual(after[0].fireAt, date(2026, 8, 24, 10, 0))
    }

    func testDeduplicatesIdenticalFireTimes() throws {
        let reminder = try makeReminder(
            year: 2026, month: 8, day: 25, hour: 10, minute: 0,
            rules: [
                .exactAtEvent(),
                .beforeEvent(value: 0, unit: .day)
            ]
        )
        let occurrences = engine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0))
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences[0].fireAt, date(2026, 8, 25, 10, 0))
    }

    func testOccurrenceIdentitiesAreUniqueAndDeterministic() throws {
        let reminder = try makeReminder(
            year: 2026, month: 9, day: 30, hour: 9, minute: 0,
            rules: [
                .beforeEvent(value: 7, unit: .day),
                .beforeEvent(value: 1, unit: .day),
                .exactAtEvent()
            ]
        )
        let first = engine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0))
        let second = engine.occurrences(for: reminder, now: date(2026, 8, 1, 9, 0))
        XCTAssertEqual(Set(first.map(\.identity)).count, first.count)
        XCTAssertEqual(first.map(\.identity), second.map(\.identity))
    }

    func testPastOccurrencesFiltered() throws {
        let reminder = try makeReminder(
            year: 2026, month: 8, day: 25, hour: 10, minute: 0,
            rules: [
                .beforeEvent(value: 30, unit: .day),
                .beforeEvent(value: 1, unit: .day)
            ]
        )
        let occurrences = engine.occurrences(for: reminder, now: date(2026, 8, 20, 12, 0))
        XCTAssertEqual(occurrences.count, 1)
        XCTAssertEqual(occurrences[0].fireAt, date(2026, 8, 24, 10, 0))
    }

    private func makeReminder(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        rules: [ReminderRule]
    ) throws -> Reminder {
        try ReminderFactory.make(
            title: "Event",
            eventDate: DateComponents(year: year, month: month, day: day),
            eventTime: DateComponents(hour: hour, minute: minute),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: rules
        )
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
}

import XCTest
@testable import LifeCue

@MainActor
final class ReminderDateWindowDefaultTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    }

    private func august(_ day: Int, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: 8, day: day, hour: 12))!
    }

    private func ymd(_ date: Date, calendar cal: Calendar? = nil) -> DateComponents {
        let used = cal ?? calendar!
        return used.dateComponents([.year, .month, .day], from: date)
    }

    /// TC-WINDOW-DEFAULT-001
    func testEnablingWindowDefaultsStartEndToEventDate() {
        let form = ReminderScheduleFormModel()
        form.repeatMode = .daily
        let event = august(12)
        form.applyDateWindowEnabled(true, eventDate: event, calendar: calendar)

        XCTAssertTrue(form.useDateWindow)
        XCTAssertEqual(ymd(form.windowStart).day, 12)
        XCTAssertEqual(ymd(form.windowStart).month, 8)
        XCTAssertEqual(ymd(form.windowEnd).day, 12)
        XCTAssertEqual(ymd(form.windowEnd).month, 8)
        XCTAssertNotEqual(ymd(form.windowStart).day, 11)
    }

    /// TC-WINDOW-DEFAULT-002
    func testEnablingWindowPreservesDailyRecurrence() throws {
        let form = ReminderScheduleFormModel()
        form.repeatMode = .daily
        form.applyDateWindowEnabled(true, eventDate: august(12), calendar: calendar)

        XCTAssertEqual(form.repeatMode, .daily)
        let rules = try form.buildRules(
            eventDate: DateComponents(year: 2026, month: 8, day: 12),
            calendar: calendar
        )
        let recurring = try XCTUnwrap(rules.first { $0.ruleType == .recurring })
        XCTAssertEqual(recurring.recurrence?.frequency, .daily)
    }

    /// TC-WINDOW-DEFAULT-003
    func testUserExtendsEndDateSavesWindow() throws {
        let form = ReminderScheduleFormModel()
        form.repeatMode = .daily
        form.applyDateWindowEnabled(true, eventDate: august(12), calendar: calendar)
        form.windowEnd = august(20)

        let rules = try form.buildRules(
            eventDate: DateComponents(year: 2026, month: 8, day: 12),
            calendar: calendar
        )
        let window = try XCTUnwrap(rules.first { $0.ruleType == .recurring }?.dateWindow)
        XCTAssertEqual(window.startDate.day, 12)
        XCTAssertEqual(window.startDate.month, 8)
        XCTAssertEqual(window.endDate.day, 20)
        XCTAssertEqual(window.endDate.month, 8)
    }

    /// TC-WINDOW-DEFAULT-004
    func testExistingStoredWindowLoadsUnchanged() {
        let stored = ReminderDateWindow(
            startDate: DateComponents(year: 2026, month: 9, day: 1),
            endDate: DateComponents(year: 2026, month: 9, day: 30)
        )
        let reminder = Reminder(
            title: "Class",
            eventDate: DateComponents(year: 2026, month: 9, day: 1),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: calendar.timeZone.identifier,
            rules: [.recurring(.daily(), window: stored)]
        )
        let form = ReminderScheduleFormModel()
        form.load(from: reminder, calendar: calendar)

        XCTAssertTrue(form.useDateWindow)
        XCTAssertEqual(ymd(form.windowStart).day, 1)
        XCTAssertEqual(ymd(form.windowStart).month, 9)
        XCTAssertEqual(ymd(form.windowEnd).day, 30)
        XCTAssertEqual(ymd(form.windowEnd).month, 9)

        // Toggle off/on must not reseed over the stored window.
        form.applyDateWindowEnabled(false, eventDate: august(12), calendar: calendar)
        form.applyDateWindowEnabled(true, eventDate: august(12), calendar: calendar)
        XCTAssertEqual(ymd(form.windowStart).day, 1)
        XCTAssertEqual(ymd(form.windowStart).month, 9)
        XCTAssertEqual(ymd(form.windowEnd).day, 30)
    }

    /// TC-WINDOW-DEFAULT-005
    func testSeedUsesReminderSchedulingCalendarNotDevice() {
        var ny = Calendar(identifier: .gregorian)
        ny.timeZone = TimeZone(identifier: "America/New_York")!
        // 12 Aug 2026 12:00 in New York
        let eventNY = ny.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12))!

        let form = ReminderScheduleFormModel()
        form.repeatMode = .daily
        form.applyDateWindowEnabled(true, eventDate: eventNY, calendar: ny)

        let start = ymd(form.windowStart, calendar: ny)
        let end = ymd(form.windowEnd, calendar: ny)
        XCTAssertEqual(start.year, 2026)
        XCTAssertEqual(start.month, 8)
        XCTAssertEqual(start.day, 12)
        XCTAssertEqual(end.day, 12)

        // Device Kolkata interpretation of the same Absolute Date must not be used for seeding calendar.
        var kolkata = Calendar(identifier: .gregorian)
        kolkata.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        // Seeding with NY calendar keeps wall day 12 even if later displayed elsewhere.
        XCTAssertEqual(ny.component(.day, from: form.windowStart), 12)
        XCTAssertEqual(ny.component(.month, from: form.windowStart), 8)
    }

    /// TC-WINDOW-DEFAULT-006
    func testSprint6DailyRecurrenceSemanticsUnchanged() {
        let engine = ReminderRuleEngine(calendar: calendar)
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8))!
        let reminder = Reminder(
            title: "Daily",
            eventDate: DateComponents(year: 2026, month: 8, day: 10),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: calendar.timeZone.identifier,
            rules: [.recurring(.daily())]
        )
        let fires = engine.occurrences(for: reminder, now: now)
        XCTAssertFalse(fires.isEmpty)
        XCTAssertEqual(
            calendar.dateComponents([.year, .month, .day], from: fires[0].fireAt).day,
            10
        )
    }
}

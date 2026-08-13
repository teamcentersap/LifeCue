import XCTest
@testable import LifeCue

final class ReminderHomeClassifierTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
    }

    func testSectionsForTodayUpcomingOverdue() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9))!

        let overdue = try ReminderFactory.make(
            title: "Past due",
            eventDate: DateComponents(year: 2026, month: 8, day: 9),
            now: now
        )
        let today = try ReminderFactory.make(
            title: "Today item",
            eventDate: DateComponents(year: 2026, month: 8, day: 10),
            eventTime: DateComponents(hour: 16, minute: 0),
            now: now
        )
        let upcoming = try ReminderFactory.make(
            title: "Future item",
            eventDate: DateComponents(year: 2026, month: 8, day: 18),
            now: now
        )
        var completed = try ReminderFactory.make(
            title: "Done",
            eventDate: DateComponents(year: 2026, month: 8, day: 10),
            now: now
        )
        completed.status = .completed

        let classifier = ReminderHomeClassifier(calendar: calendar, now: now)
        let grouped = classifier.grouped([overdue, today, upcoming, completed])

        XCTAssertEqual(grouped[.overdue]?.map(\.title), ["Past due"])
        XCTAssertEqual(grouped[.today]?.map(\.title), ["Today item"])
        XCTAssertEqual(grouped[.upcoming]?.map(\.title), ["Future item"])
    }

    func testCompletedRemindersAreExcludedFromHome() throws {
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        var reminder = try ReminderFactory.make(
            title: "Completed today",
            eventDate: DateComponents(year: 2026, month: 8, day: 10),
            now: now
        )
        reminder.status = .completed

        let classifier = ReminderHomeClassifier(calendar: calendar, now: now)
        XCTAssertNil(classifier.section(for: reminder))
    }
}

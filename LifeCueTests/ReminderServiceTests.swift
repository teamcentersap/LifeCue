import XCTest
@testable import LifeCue

@MainActor
final class ReminderServiceTests: XCTestCase {
    private var repository: InMemoryReminderRepository!
    private var notifications: FakeNotificationScheduler!
    private var service: ReminderService!
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        repository = InMemoryReminderRepository()
        notifications = FakeNotificationScheduler()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        service = ReminderService(
            repository: repository,
            notificationScheduler: notifications,
            ruleEngine: ReminderRuleEngine(calendar: cal),
            calendar: calendar,
            clock: { [now] in now! }
        )
    }

    func testCreateWithoutPersonOrContext() async throws {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let created = try await service.create(
            title: "Doctor appointment",
            eventDate: eventDate,
            includeTime: true,
            eventTime: calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16, minute: 0)),
            note: "Take previous reports."
        ).reminder

        XCTAssertEqual(created.title, "Doctor appointment")
        XCTAssertEqual(created.eventDate.day, 18)
        XCTAssertEqual(created.eventTime?.hour, 16)
        XCTAssertEqual(created.note, "Take previous reports.")
        XCTAssertFalse(created.rules.isEmpty)
        XCTAssertEqual(try service.allReminders().count, 1)
    }

    func testNoteEditPersistsExactly() async throws {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        var reminder = try await service.create(
            title: "Science project",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: "Bring cardboard"
        ).reminder

        reminder.note = "Bring cardboard and 2 photographs."
        _ = try await service.update(reminder)

        let stored = try service.reminder(id: reminder.id)
        XCTAssertEqual(stored?.note, "Bring cardboard and 2 photographs.")
    }

    func testEditUpdatesFields() async throws {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        var reminder = try await service.create(
            title: "Science project",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: nil
        ).reminder

        reminder.title = "Science fair project"
        reminder.eventDate = DateComponents(year: 2026, month: 8, day: 26)
        reminder.eventTime = DateComponents(hour: 10, minute: 30)
        _ = try await service.update(reminder)

        let stored = try XCTUnwrap(service.reminder(id: reminder.id))
        XCTAssertEqual(stored.title, "Science fair project")
        XCTAssertEqual(stored.eventDate.day, 26)
        XCTAssertEqual(stored.eventTime?.hour, 10)
        XCTAssertEqual(stored.eventTime?.minute, 30)
    }

    func testDeleteRemovesReminder() async throws {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        let reminder = try await service.create(
            title: "Temporary",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: nil
        ).reminder

        try await service.delete(id: reminder.id)
        XCTAssertNil(try service.reminder(id: reminder.id))
        XCTAssertTrue(try service.allReminders().isEmpty)
    }

    func testCompleteMarksStatusAndTimestamp() async throws {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10))!
        let reminder = try await service.create(
            title: "Due today",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: nil
        ).reminder

        _ = try await service.complete(id: reminder.id)
        let stored = try XCTUnwrap(service.reminder(id: reminder.id))
        XCTAssertEqual(stored.status, .completed)
        XCTAssertEqual(stored.completedAt, now)

        let sections = try service.homeSections()
        XCTAssertTrue((sections[.today] ?? []).isEmpty)
    }

    func testPersistenceAcrossRepositoryReload() async throws {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12))!
        let reminder = try await service.create(
            title: "Persisted reminder",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: "Keep me"
        ).reminder

        let relaunched = ReminderService(
            repository: repository,
            notificationScheduler: FakeNotificationScheduler(),
            calendar: calendar,
            clock: { [now] in now! }
        )
        let stored = try XCTUnwrap(relaunched.reminder(id: reminder.id))
        XCTAssertEqual(stored.title, "Persisted reminder")
        XCTAssertEqual(stored.note, "Keep me")
        XCTAssertFalse(stored.rules.isEmpty)
    }

    func testRulesPersistWithReminder() async throws {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 25))!
        let reminder = try await service.create(
            title: "With rules",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: nil,
            rules: [
                .beforeEvent(value: 1, unit: .week),
                .beforeEvent(value: 1, unit: .day)
            ]
        ).reminder
        let stored = try XCTUnwrap(service.reminder(id: reminder.id))
        XCTAssertEqual(stored.rules.count, 2)
        XCTAssertEqual(stored.rules.map(\.offsetValue), [1, 1])
    }
}

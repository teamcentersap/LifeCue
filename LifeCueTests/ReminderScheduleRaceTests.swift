import XCTest
@testable import LifeCue

@MainActor
final class ReminderScheduleRaceTests: XCTestCase {
    private var repository: InMemoryReminderRepository!
    private var delayed: DelayedNotificationScheduler!
    private var service: ReminderService!
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        repository = InMemoryReminderRepository()
        delayed = DelayedNotificationScheduler()
        delayed.status = .authorized
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        service = ReminderService(
            repository: repository,
            notificationScheduler: delayed,
            ruleEngine: ReminderRuleEngine(calendar: cal),
            calendar: calendar,
            clock: { [unowned self] in self.now }
        )
    }

    override func tearDown() {
        delayed.releasePausedSchedules()
        super.tearDown()
    }

    /// TEST 1: in-flight schedule + complete → no leftover notification
    func testInFlightScheduleThenCompleteLeavesNoNotification() async throws {
        let reminder = try await createBaselineReminder(
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        )
        XCTAssertEqual(delayed.scheduled.count, 2)

        delayed.shouldPauseSchedules = true
        let updateTask = Task {
            var edited = reminder
            edited.title = "Updating"
            return try await service.update(edited)
        }

        let paused = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(paused)

        _ = try await service.complete(id: reminder.id)
        delayed.shouldPauseSchedules = false
        delayed.releasePausedSchedules()
        _ = try await updateTask.value

        XCTAssertTrue(
            delayed.scheduled.isEmpty,
            "Complete must not leave a future notification after a superseded in-flight schedule"
        )
        XCTAssertEqual(try service.reminder(id: reminder.id)?.status, .completed)
    }

    /// TEST 2: in-flight schedule + delete → no leftover notification
    func testInFlightScheduleThenDeleteLeavesNoNotification() async throws {
        let reminder = try await createBaselineReminder(rules: [.exactAtEvent()])
        XCTAssertEqual(delayed.scheduled.count, 1)

        delayed.shouldPauseSchedules = true
        let updateTask = Task {
            var edited = reminder
            edited.note = "race"
            return try await service.update(edited)
        }

        let pausedForDelete = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(pausedForDelete)
        try await service.delete(id: reminder.id)
        delayed.shouldPauseSchedules = false
        delayed.releasePausedSchedules()
        _ = try? await updateTask.value

        XCTAssertTrue(delayed.scheduled.isEmpty)
        XCTAssertNil(try service.reminder(id: reminder.id))
    }

    /// TEST 3: schedule A paused → edit to B → release A → only B remains
    func testSupersededScheduleDoesNotOverwriteNewerEdit() async throws {
        let week = ReminderRule.beforeEvent(value: 1, unit: .week)
        let day = ReminderRule.beforeEvent(value: 1, unit: .day)
        let atEvent = ReminderRule.exactAtEvent()
        let reminder = try await createBaselineReminder(rules: [week, day, atEvent])
        XCTAssertEqual(delayed.scheduled.count, 3)

        delayed.shouldPauseSchedules = true
        let scheduleA = Task {
            var edited = reminder
            // Same multi-rule schedule (A)
            edited.title = "Schedule A"
            edited.rules = [week, day, atEvent]
            return try await service.update(edited)
        }

        let pausedForEdit = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(pausedForEdit)

        // Newer operation B: single exact rule, unpaused.
        delayed.shouldPauseSchedules = false
        var editedB = reminder
        editedB.title = "Schedule B"
        editedB.rules = [atEvent]
        _ = try await service.update(editedB)
        XCTAssertEqual(delayed.scheduled.count, 1)
        XCTAssertEqual(delayed.scheduled.first?.title, "Schedule B")

        // Release A; compensating cancel must not leave A's identifiers.
        delayed.releasePausedSchedules()
        _ = try await scheduleA.value

        XCTAssertEqual(delayed.scheduled.count, 1)
        XCTAssertEqual(delayed.scheduled.first?.title, "Schedule B")
        XCTAssertEqual(try service.reminder(id: reminder.id)?.title, "Schedule B")
    }

    /// TEST 4: in-flight schedule + snooze → only current intended schedule remains
    func testInFlightScheduleThenSnoozeKeepsCurrentScheduleOnly() async throws {
        let day = ReminderRule.beforeEvent(value: 1, unit: .day)
        let atEvent = ReminderRule.exactAtEvent()
        let reminder = try await createBaselineReminder(rules: [day, atEvent])

        delayed.shouldPauseSchedules = true
        let staleUpdate = Task {
            var edited = reminder
            edited.title = "Stale update"
            edited.rules = [day, atEvent]
            return try await service.update(edited)
        }

        let pausedForSnooze = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(pausedForSnooze)

        delayed.shouldPauseSchedules = false
        _ = try await service.snooze(id: reminder.id, option: .laterToday)
        let afterSnoozeIDs = Set(delayed.scheduled.map(\.identifier))
        XCTAssertTrue(afterSnoozeIDs.contains { id in
            id.contains(ReminderRuleEngine.snoozeRuleNamespace.uuidString)
        })
        XCTAssertEqual(delayed.scheduled.count, 3) // day + atEvent + snooze

        delayed.releasePausedSchedules()
        _ = try await staleUpdate.value

        let finalIDs = Set(delayed.scheduled.map(\.identifier))
        XCTAssertEqual(finalIDs, afterSnoozeIDs)
        XCTAssertEqual(delayed.scheduled.count, 3)
        XCTAssertNotNil(try service.reminder(id: reminder.id)?.snooze)
    }

    /// TEST 5: multiple identifiers from superseded op are all removed
    func testSupersededMultiIdentifierScheduleCompensatesAll() async throws {
        let rules: [ReminderRule] = [
            .beforeEvent(value: 1, unit: .week),
            .beforeEvent(value: 1, unit: .day),
            .exactAtEvent()
        ]
        let reminder = try await createBaselineReminder(rules: rules)
        XCTAssertEqual(delayed.scheduled.count, 3)

        delayed.shouldPauseSchedules = true
        let multiUpdate = Task {
            var edited = reminder
            edited.title = "Multi stale"
            edited.rules = rules
            return try await service.update(edited)
        }

        let pausedForMulti = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(pausedForMulti)
        _ = try await service.complete(id: reminder.id)
        delayed.shouldPauseSchedules = false
        delayed.releasePausedSchedules()
        _ = try await multiUpdate.value

        XCTAssertTrue(delayed.scheduled.isEmpty)
        let leftover = delayed.scheduled.filter { $0.reminderID == reminder.id }
        XCTAssertTrue(leftover.isEmpty)
    }

    private func createBaselineReminder(rules: [ReminderRule]) async throws -> Reminder {
        delayed.shouldPauseSchedules = false
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        return try await service.create(
            title: "Baseline",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: rules
        ).reminder
    }
}

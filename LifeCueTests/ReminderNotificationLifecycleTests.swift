import XCTest
@testable import LifeCue

@MainActor
final class ReminderNotificationLifecycleTests: XCTestCase {
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
            clock: { [unowned self] in self.now }
        )
    }

    func testAuthorizedSchedulesNotifications() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let result = try await service.create(
            title: "Doctor Appointment",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [
                .beforeEvent(value: 1, unit: .week),
                .beforeEvent(value: 1, unit: .day),
                .exactAtEvent()
            ]
        )

        XCTAssertEqual(notifications.scheduled.count, 3)
        XCTAssertEqual(result.scheduleOutcome, .scheduled(3))
    }

    func testDeniedPermissionKeepsReminderWithoutNotifications() async throws {
        notifications.status = .denied
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let result = try await service.create(
            title: "Still saved",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: "Note",
            rules: [.beforeEvent(value: 1, unit: .day)]
        )

        XCTAssertEqual(try service.allReminders().count, 1)
        XCTAssertEqual(result.reminder.note, "Note")
        XCTAssertEqual(result.scheduleOutcome, .permissionDenied)
        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    func testSchedulingFailureKeepsReminderAndIsObservable() async throws {
        notifications.status = .authorized
        notifications.shouldFailSchedule = true
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let result = try await service.create(
            title: "Persisted anyway",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: "Keep me",
            rules: [.exactAtEvent()]
        )

        XCTAssertEqual(try service.allReminders().count, 1)
        XCTAssertEqual(result.reminder.note, "Keep me")
        XCTAssertTrue(result.scheduleFailed)
        XCTAssertEqual(result.scheduleOutcome, .schedulingFailed)
    }

    func testEditDoesNotLeaveStaleNotifications() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 10))!
        var reminder = try await service.create(
            title: "Original",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [
                .beforeEvent(value: 7, unit: .day),
                .beforeEvent(value: 1, unit: .day)
            ]
        ).reminder
        let firstIDs = Set(notifications.scheduled.map(\.identifier))
        XCTAssertEqual(firstIDs.count, 2)

        reminder.title = "Updated"
        reminder.rules = [.exactAtEvent()]
        _ = try await service.update(reminder)

        XCTAssertEqual(notifications.scheduled.count, 1)
        XCTAssertEqual(notifications.scheduled.first?.title, "Updated")
        for id in firstIDs {
            XCTAssertTrue(notifications.cancelledIdentifiers.contains(id))
        }
    }

    func testDeleteLeavesNoNotification() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "Delete me",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        ).reminder

        try await service.delete(id: reminder.id)
        XCTAssertTrue(notifications.scheduled.isEmpty)
        XCTAssertNil(try service.reminder(id: reminder.id))
    }

    func testCompleteLeavesNoFutureNotification() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "Complete me",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        ).reminder
        _ = try await service.complete(id: reminder.id)
        XCTAssertTrue(notifications.scheduled.isEmpty)
        XCTAssertEqual(try service.reminder(id: reminder.id)?.status, .completed)
    }

    func testSnoozeKeepsLaterStandingNotifications() async throws {
        notifications.status = .authorized
        // Event far enough that 7-day / 1-day / at-event are all still future.
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let week = ReminderRule.beforeEvent(value: 1, unit: .week)
        let day = ReminderRule.beforeEvent(value: 1, unit: .day)
        let atEvent = ReminderRule.exactAtEvent()
        let reminder = try await service.create(
            title: "Snooze carefully",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [week, day, atEvent]
        ).reminder
        XCTAssertEqual(notifications.scheduled.count, 3)

        _ = try await service.snooze(id: reminder.id, option: .laterToday)

        let stored = try XCTUnwrap(service.reminder(id: reminder.id))
        XCTAssertEqual(stored.rules.count, 3)
        XCTAssertNotNil(stored.snooze)
        // Standing future notifications remain, plus snooze.
        XCTAssertEqual(notifications.scheduled.count, 4)
        XCTAssertTrue(notifications.scheduled.contains { $0.ruleID == day.id })
        XCTAssertTrue(notifications.scheduled.contains { $0.ruleID == atEvent.id })
        XCTAssertTrue(notifications.scheduled.contains { $0.ruleID == week.id })
        XCTAssertTrue(notifications.scheduled.contains {
            $0.ruleID == ReminderRuleEngine.snoozeRuleNamespace
        })
    }

    func testSnoozeFollowedByEditClearsSnoozeAndReschedules() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        var reminder = try await service.create(
            title: "Edit after snooze",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        ).reminder
        _ = try await service.snooze(id: reminder.id, option: .tomorrow)
        XCTAssertNotNil(try service.reminder(id: reminder.id)?.snooze)

        reminder.snooze = ReminderSnoozeState(until: now.addingTimeInterval(3600))
        reminder.title = "Edited"
        reminder.rules = [.exactAtEvent()]
        _ = try await service.update(reminder)

        let stored = try XCTUnwrap(service.reminder(id: reminder.id))
        XCTAssertNil(stored.snooze)
        XCTAssertEqual(stored.title, "Edited")
        XCTAssertEqual(notifications.scheduled.count, 1)
    }

    func testSnoozeFollowedByDelete() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "Delete after snooze",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent()]
        ).reminder
        _ = try await service.snooze(id: reminder.id, option: .laterToday)
        try await service.delete(id: reminder.id)
        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    func testSnoozeFollowedByComplete() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "Complete after snooze",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        ).reminder
        _ = try await service.snooze(id: reminder.id, option: .laterToday)
        _ = try await service.complete(id: reminder.id)
        XCTAssertTrue(notifications.scheduled.isEmpty)
        XCTAssertNil(try service.reminder(id: reminder.id)?.snooze)
    }

    func testSnoozeFollowedByReschedule() async throws {
        notifications.status = .authorized
        let original = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "Reschedule after snooze",
            eventDate: original,
            includeTime: true,
            eventTime: original,
            note: nil,
            rules: [.exactAtEvent()]
        ).reminder
        _ = try await service.snooze(id: reminder.id, option: .laterToday)
        let moved = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 11))!
        _ = try await service.reschedule(
            id: reminder.id,
            eventDate: moved,
            includeTime: true,
            eventTime: moved
        )
        let stored = try XCTUnwrap(service.reminder(id: reminder.id))
        XCTAssertNil(stored.snooze)
        XCTAssertEqual(notifications.scheduled.count, 1)
    }

    func testMultipleSnoozesReplaceTemporaryStateOnly() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let day = ReminderRule.beforeEvent(value: 1, unit: .day)
        let reminder = try await service.create(
            title: "Multi snooze",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [day, .exactAtEvent()]
        ).reminder
        _ = try await service.snooze(id: reminder.id, option: .laterToday)
        let firstUntil = try XCTUnwrap(service.reminder(id: reminder.id)?.snooze?.until)
        _ = try await service.snooze(id: reminder.id, option: .tomorrow)
        let secondUntil = try XCTUnwrap(service.reminder(id: reminder.id)?.snooze?.until)
        XCTAssertNotEqual(firstUntil, secondUntil)
        XCTAssertEqual(try service.reminder(id: reminder.id)?.rules.count, 2)
        XCTAssertEqual(
            notifications.scheduled.filter { $0.ruleID == ReminderRuleEngine.snoozeRuleNamespace }.count,
            1
        )
    }

    func testAppRestartWhileSnoozedPreservesStandingAndSnooze() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "Restart while snoozed",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [
                .beforeEvent(value: 1, unit: .week),
                .beforeEvent(value: 1, unit: .day),
                .exactAtEvent()
            ]
        ).reminder
        _ = try await service.snooze(id: reminder.id, option: .laterToday)

        let relaunchedNotifications = FakeNotificationScheduler()
        let relaunched = ReminderService(
            repository: repository,
            notificationScheduler: relaunchedNotifications,
            ruleEngine: ReminderRuleEngine(calendar: calendar),
            calendar: calendar,
            clock: { [unowned self] in self.now }
        )
        await relaunched.reconcileAllNotifications()

        let stored = try XCTUnwrap(relaunched.reminder(id: reminder.id))
        XCTAssertEqual(stored.rules.count, 3)
        XCTAssertNotNil(stored.snooze)
        XCTAssertEqual(relaunchedNotifications.scheduled.count, 4)
    }

    func testSnoozeExpiryClearsTemporaryStateOnReconcile() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "Expired snooze",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent()]
        ).reminder
        _ = try await service.snooze(id: reminder.id, option: .custom(now.addingTimeInterval(60)))
        now = now.addingTimeInterval(120)
        await service.reconcileAllNotifications()

        let stored = try XCTUnwrap(service.reminder(id: reminder.id))
        XCTAssertNil(stored.snooze)
        XCTAssertEqual(notifications.scheduled.count, 1)
        XCTAssertEqual(notifications.scheduled.first?.ruleID, stored.rules.first?.id)
    }

    func testEmptyRulesPersistWithZeroNotifications() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        let result = try await service.create(
            title: "No notifications please",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: "Still important",
            rules: []
        )
        XCTAssertTrue(result.reminder.rules.isEmpty)
        XCTAssertEqual(result.scheduleOutcome, .nothingToSchedule)
        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    func testUpdateToEmptyRulesCancelsAllNotifications() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        var reminder = try await service.create(
            title: "Had reminders",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        ).reminder
        reminder.rules = []
        _ = try await service.update(reminder)
        XCTAssertTrue(try XCTUnwrap(service.reminder(id: reminder.id)).rules.isEmpty)
        XCTAssertTrue(notifications.scheduled.isEmpty)
    }

    func testReconcileRemovesOrphanNotifications() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "Keep",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent()]
        ).reminder

        let orphanReminderID = UUID()
        let orphan = ScheduledNotificationRequest(
            identifier: NotificationIdentifier.occurrence(
                reminderID: orphanReminderID,
                generation: 1,
                ruleID: UUID(),
                occurrenceKey: "t1"
            ),
            fireAt: now.addingTimeInterval(3600),
            title: "Orphan",
            body: "Should go",
            reminderID: orphanReminderID,
            ruleID: UUID(),
            occurrenceKey: "t1",
            timeZoneIdentifier: "Asia/Kolkata"
        )
        try await notifications.schedule(orphan)
        XCTAssertEqual(notifications.scheduled.count, 2)

        await service.reconcileAllNotifications()
        XCTAssertEqual(notifications.scheduled.count, 1)
        XCTAssertEqual(notifications.scheduled.first?.reminderID, reminder.id)
    }

    func testSchedulingSameReminderTwiceDoesNotDuplicate() async throws {
        notifications.status = .authorized
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "No dupes",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent()]
        ).reminder
        _ = try await service.update(reminder)
        _ = try await service.update(reminder)
        XCTAssertEqual(notifications.scheduled.count, 1)
    }

    func testRescheduleUpdatesFireTimes() async throws {
        notifications.status = .authorized
        let original = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "Reschedule",
            eventDate: original,
            includeTime: true,
            eventTime: original,
            note: nil,
            rules: [.exactAtEvent()]
        ).reminder
        let firstFire = notifications.scheduled.first?.fireAt
        let moved = calendar.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 11))!
        _ = try await service.reschedule(
            id: reminder.id,
            eventDate: moved,
            includeTime: true,
            eventTime: moved
        )
        XCTAssertNotEqual(firstFire, notifications.scheduled.first?.fireAt)
    }

    func testNotDeterminedRequestsAuthorizationOnceOnCreate() async throws {
        notifications.status = .notDetermined
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
        _ = try await service.create(
            title: "Ask once",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: nil,
            rules: [.beforeEvent(value: 1, unit: .day)]
        )
        XCTAssertTrue(notifications.didRequestAuthorization)
    }

    func testLaterScheduleGenerationSupersedesEarlier() async throws {
        // Deterministic race: earlier in-flight schedule must not overwrite a later edit.
        let delayed = DelayedNotificationScheduler(backing: notifications)
        delayed.status = .authorized
        service = ReminderService(
            repository: repository,
            notificationScheduler: delayed,
            ruleEngine: ReminderRuleEngine(calendar: calendar),
            calendar: calendar,
            clock: { [unowned self] in self.now }
        )

        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!
        let reminder = try await service.create(
            title: "Race",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        ).reminder

        delayed.shouldPauseSchedules = true
        let earlier = Task {
            var stale = reminder
            stale.title = "Earlier"
            stale.rules = [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
            return try await service.update(stale)
        }
        let paused = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(paused)

        delayed.shouldPauseSchedules = false
        var edited = reminder
        edited.title = "Later"
        edited.rules = [.exactAtEvent()]
        _ = try await service.update(edited)

        delayed.releasePausedSchedules()
        _ = try await earlier.value

        // Final scheduled set must match the latest standing rules (1 notification).
        XCTAssertEqual(notifications.scheduled.count, 1)
        XCTAssertEqual(notifications.scheduled.first?.title, "Later")
        let stored = try XCTUnwrap(service.reminder(id: reminder.id))
        XCTAssertEqual(stored.rules.count, 1)
        XCTAssertEqual(stored.title, "Later")
    }
}

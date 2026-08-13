import XCTest
@testable import LifeCue

@MainActor
final class ReminderReplenishmentTests: XCTestCase {
    private var calendar: Calendar!
    private var timeZone: TimeZone!
    private var now: Date!

    override func setUp() {
        super.setUp()
        timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8))!
    }

    private func makeService(
        clock: @escaping () -> Date
    ) -> (ReminderService, InMemoryReminderRepository, FakeNotificationScheduler) {
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        let repo = InMemoryReminderRepository()
        let service = ReminderService(
            repository: repo,
            notificationScheduler: scheduler,
            ruleEngine: ReminderRuleEngine(calendar: calendar),
            calendar: calendar,
            clock: clock
        )
        return (service, repo, scheduler)
    }

    /// TC-RECOVER-001 Initial recurring occurrences are scheduled.
    func testInitialRecurringOccurrencesScheduled() async throws {
        var current = now!
        let (service, _, scheduler) = makeService(clock: { current })
        _ = try await service.create(
            title: "Daily",
            eventDate: current,
            includeTime: true,
            eventTime: current,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        XCTAssertEqual(
            scheduler.scheduled.count,
            ReminderSchedulingPolicy.default.maxOccurrencesPerReminder
        )
    }

    /// TC-RECOVER-002 After occurrences consumed, reconcile schedules future ones.
    /// TC-RECOVER-004 Continues beyond first 16.
    func testForegroundReconcileReplenishesBeyondInitialBatch() async throws {
        var current = now!
        let (service, _, scheduler) = makeService(clock: { current })
        let created = try await service.create(
            title: "Daily",
            eventDate: current,
            includeTime: true,
            eventTime: calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9))!,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        let firstBatch = Set(scheduler.scheduled.map(\.identifier))
        XCTAssertEqual(firstBatch.count, 16)

        // Advance past the first batch window (16 days later + buffer).
        current = calendar.date(byAdding: .day, value: 20, to: now)!
        // Simulate delivered notifications disappearing from pending queue.
        scheduler.reset()
        scheduler.status = .authorized

        await service.reconcileAllNotifications()

        let secondBatch = scheduler.scheduled.filter {
            $0.identifier.contains(created.reminder.id.uuidString)
        }
        XCTAssertFalse(secondBatch.isEmpty)
        XCTAssertEqual(secondBatch.count, 16)
        // New fire times should be after the advanced clock.
        XCTAssertTrue(secondBatch.allSatisfy { $0.fireAt > current })
        // Identifiers differ from the consumed first batch.
        XCTAssertTrue(Set(secondBatch.map(\.identifier)).isDisjoint(with: firstBatch))
    }

    /// TC-RECOVER-003 Repeated reconcile does not duplicate.
    func testRepeatedReconcileDoesNotDuplicate() async throws {
        var current = now!
        let (service, _, scheduler) = makeService(clock: { current })
        _ = try await service.create(
            title: "Daily",
            eventDate: current,
            includeTime: true,
            eventTime: calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9))!,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        let afterCreate = scheduler.scheduled.count
        await service.reconcileAllNotifications()
        await service.reconcileAllNotifications()
        XCTAssertEqual(scheduler.scheduled.count, afterCreate)
        XCTAssertEqual(Set(scheduler.scheduled.map(\.identifier)).count, afterCreate)
    }

    /// TC-RECOVER-005 Date-window not exceeded during replenishment.
    func testReplenishRespectsDateWindow() async throws {
        var current = now!
        let (service, _, scheduler) = makeService(clock: { current })
        let window = ReminderDateWindow(
            startDate: DateComponents(year: 2026, month: 8, day: 10),
            endDate: DateComponents(year: 2026, month: 8, day: 20)
        )
        _ = try await service.create(
            title: "Windowed",
            eventDate: current,
            includeTime: true,
            eventTime: calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9))!,
            note: nil,
            rules: [.recurring(.daily(), window: window)],
            timeZoneIdentifier: timeZone.identifier
        )
        current = calendar.date(byAdding: .day, value: 5, to: now)!
        scheduler.reset()
        scheduler.status = .authorized
        await service.reconcileAllNotifications()

        let end = calendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 23, minute: 59))!
        XCTAssertTrue(scheduler.scheduled.allSatisfy { $0.fireAt <= end })
        XCTAssertFalse(scheduler.scheduled.isEmpty)
    }

    /// TC-RECOVER-006 Completed not replenished.
    func testCompletedNotReplenished() async throws {
        var current = now!
        let (service, _, scheduler) = makeService(clock: { current })
        let created = try await service.create(
            title: "Daily",
            eventDate: current,
            includeTime: true,
            eventTime: current,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        _ = try await service.complete(id: created.reminder.id)
        current = calendar.date(byAdding: .day, value: 20, to: now)!
        await service.reconcileAllNotifications()
        XCTAssertTrue(scheduler.scheduled.filter { $0.identifier.contains(created.reminder.id.uuidString) }.isEmpty)
    }

    /// TC-RECOVER-007 Deleted not replenished.
    func testDeletedNotReplenished() async throws {
        var current = now!
        let (service, _, scheduler) = makeService(clock: { current })
        let created = try await service.create(
            title: "Daily",
            eventDate: current,
            includeTime: true,
            eventTime: current,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        let id = created.reminder.id
        try await service.delete(id: id)
        current = calendar.date(byAdding: .day, value: 20, to: now)!
        await service.reconcileAllNotifications()
        XCTAssertTrue(scheduler.scheduled.filter { $0.identifier.contains(id.uuidString) }.isEmpty)
    }
}

@MainActor
final class ReminderReconcileRaceTests: XCTestCase {
    private var calendar: Calendar!
    private var timeZone: TimeZone!
    private var now: Date!

    override func setUp() {
        super.setUp()
        timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
    }

    private func makeHarness() -> (
        ReminderService,
        InMemoryReminderRepository,
        DelayedNotificationScheduler,
        FakeNotificationScheduler
    ) {
        let base = FakeNotificationScheduler()
        base.status = .authorized
        let delayed = DelayedNotificationScheduler(backing: base)
        let repo = InMemoryReminderRepository()
        let service = ReminderService(
            repository: repo,
            notificationScheduler: delayed,
            ruleEngine: ReminderRuleEngine(calendar: calendar),
            calendar: calendar,
            clock: { self.now }
        )
        return (service, repo, delayed, base)
    }

    private func createDaily(
        _ service: ReminderService
    ) async throws -> Reminder {
        try await service.create(
            title: "Daily",
            eventDate: now,
            includeTime: true,
            eventTime: now,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        ).reminder
    }

    /// TC-RECON-RACE-001 snapshot → delete → stale reconcile finishes → none remain
    func testStaleReconcileAfterDeleteLeavesNoNotification() async throws {
        let (service, _, delayed, base) = makeHarness()
        let reminder = try await createDaily(service)
        XCTAssertFalse(base.scheduled.isEmpty)

        delayed.shouldPauseSchedules = true
        let reconcileTask = Task { await service.reconcileAllNotifications() }
        let paused = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(paused)

        try await service.delete(id: reminder.id)
        delayed.shouldPauseSchedules = false
        delayed.releasePausedSchedules()
        await reconcileTask.value

        XCTAssertTrue(base.scheduled.filter { $0.identifier.contains(reminder.id.uuidString) }.isEmpty)
        XCTAssertNil(try service.reminder(id: reminder.id))
    }

    /// TC-RECON-RACE-002 snapshot → complete
    func testStaleReconcileAfterCompleteLeavesNoNotification() async throws {
        let (service, _, delayed, base) = makeHarness()
        let reminder = try await createDaily(service)

        delayed.shouldPauseSchedules = true
        let reconcileTask = Task { await service.reconcileAllNotifications() }
        let pausedComplete = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(pausedComplete)

        _ = try await service.complete(id: reminder.id)
        delayed.shouldPauseSchedules = false
        delayed.releasePausedSchedules()
        await reconcileTask.value

        XCTAssertTrue(base.scheduled.filter { $0.identifier.contains(reminder.id.uuidString) }.isEmpty)
        XCTAssertEqual(try service.reminder(id: reminder.id)?.status, .completed)
    }

    /// TC-RECON-RACE-003 snapshot → edit → only new schedule remains
    func testStaleReconcileAfterEditKeepsOnlyNewSchedule() async throws {
        let (service, _, delayed, base) = makeHarness()
        let reminder = try await createDaily(service)

        delayed.shouldPauseSchedules = true
        let reconcileTask = Task { await service.reconcileAllNotifications() }
        let pausedEdit = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(pausedEdit)

        delayed.shouldPauseSchedules = false
        var edited = reminder
        edited.title = "Edited"
        // Future one-shot so scheduling produces a standing notification.
        let future = calendar.date(byAdding: .day, value: 3, to: now)!
        edited.eventDate = Reminder.dateComponents(from: future, calendar: calendar)
        edited.eventTime = Reminder.timeComponents(from: future, calendar: calendar)
        edited.rules = [.exactAtEvent()]
        _ = try await service.update(edited)

        delayed.releasePausedSchedules()
        await reconcileTask.value

        let remaining = base.scheduled.filter { $0.identifier.contains(reminder.id.uuidString) }
        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.title, "Edited")
    }

    /// TC-RECON-RACE-004 disable rule
    func testStaleReconcileAfterDisableRuleLeavesNoRecurringNotification() async throws {
        let (service, _, delayed, base) = makeHarness()
        let reminder = try await createDaily(service)

        delayed.shouldPauseSchedules = true
        let reconcileTask = Task { await service.reconcileAllNotifications() }
        let pausedDisable = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(pausedDisable)

        delayed.shouldPauseSchedules = false
        var edited = reminder
        var rule = ReminderRule.recurring(.daily())
        rule.enabled = false
        edited.rules = [rule]
        _ = try await service.update(edited)

        delayed.releasePausedSchedules()
        await reconcileTask.value

        XCTAssertTrue(base.scheduled.filter { $0.identifier.contains(reminder.id.uuidString) }.isEmpty)
    }

    /// TC-RECON-RACE-005 snooze during reconcile
    func testStaleReconcileAfterSnoozeKeepsStandingAndSnooze() async throws {
        let (service, _, delayed, base) = makeHarness()
        let reminder = try await createDaily(service)

        delayed.shouldPauseSchedules = true
        let reconcileTask = Task { await service.reconcileAllNotifications() }
        let pausedSnooze = await delayed.waitUntilPaused(count: 1)
        XCTAssertTrue(pausedSnooze)

        delayed.shouldPauseSchedules = false
        _ = try await service.snooze(id: reminder.id, option: .laterToday)

        delayed.releasePausedSchedules()
        await reconcileTask.value

        let remaining = base.scheduled.filter { $0.identifier.contains(reminder.id.uuidString) }
        XCTAssertFalse(remaining.isEmpty)
        XCTAssertNotNil(try service.reminder(id: reminder.id)?.snooze)
        // Standing recurrence still present alongside snooze.
        XCTAssertGreaterThanOrEqual(remaining.count, 2)
    }
}

final class ReminderCustomOffsetEditTests: XCTestCase {
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    }

    private func reminderWithCustomOffset() -> Reminder {
        Reminder(
            title: "Custom",
            eventDate: DateComponents(year: 2026, month: 9, day: 18),
            eventTime: DateComponents(hour: 16, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [
                .exactAtEvent(),
                .beforeEvent(value: 2, unit: .week),
                .beforeEvent(value: 1, unit: .day)
            ]
        )
    }

    /// TC-CUSTOM-EDIT-001 Load persisted custom before-event offset.
    func testLoadPersistedCustomOffset() {
        let form = ReminderScheduleFormModel()
        form.load(from: reminderWithCustomOffset(), calendar: calendar)
        XCTAssertTrue(form.useCustomBefore)
        XCTAssertEqual(form.customBeforeValue, 2)
        XCTAssertEqual(form.customBeforeUnit, .week)
        XCTAssertTrue(form.remindOneDayBefore)
    }

    /// TC-CUSTOM-EDIT-002 Save unchanged preserves custom offset.
    func testSaveUnchangedPreservesCustomOffset() throws {
        let original = reminderWithCustomOffset()
        let form = ReminderScheduleFormModel()
        form.load(from: original, calendar: calendar)
        let rules = try form.buildRules(eventDate: original.eventDate, calendar: calendar)
        XCTAssertTrue(rules.contains {
            $0.ruleType == .beforeEvent && $0.offsetValue == 2 && $0.offsetUnit == .week
        })
        XCTAssertTrue(rules.contains {
            $0.ruleType == .beforeEvent && $0.offsetValue == 1 && $0.offsetUnit == .day
        })
    }

    /// TC-CUSTOM-EDIT-003 Edit unrelated field preserves custom offset.
    func testUnrelatedChangePreservesCustomOffset() throws {
        let original = reminderWithCustomOffset()
        let form = ReminderScheduleFormModel()
        form.load(from: original, calendar: calendar)
        // Simulate title-only edit: schedule model untouched.
        let rules = try form.buildRules(eventDate: original.eventDate, calendar: calendar)
        XCTAssertTrue(rules.contains {
            $0.ruleType == .beforeEvent && $0.offsetValue == 2 && $0.offsetUnit == .week
        })
    }

    /// TC-CUSTOM-EDIT-004 Multiple offsets including custom survive edit.
    func testMultipleOffsetsIncludingCustomSurvive() throws {
        let original = Reminder(
            title: "Multi",
            eventDate: DateComponents(year: 2026, month: 9, day: 18),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [
                .beforeEvent(value: 10, unit: .minute),
                .beforeEvent(value: 3, unit: .day),
                .beforeEvent(value: 1, unit: .week)
            ]
        )
        let form = ReminderScheduleFormModel()
        form.load(from: original, calendar: calendar)
        let rules = try form.buildRules(eventDate: original.eventDate, calendar: calendar)
        XCTAssertTrue(rules.contains { $0.offsetValue == 10 && $0.offsetUnit == .minute })
        XCTAssertTrue(rules.contains { $0.offsetValue == 1 && $0.offsetUnit == .week })
        XCTAssertTrue(rules.contains { $0.offsetValue == 3 && $0.offsetUnit == .day })
    }

    /// Custom offset remains after edit + reconciliation.
    @MainActor
    func testCustomOffsetSurvivesEditAndReconcile() async throws {
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        let repo = InMemoryReminderRepository()
        let service = ReminderService(
            repository: repo,
            notificationScheduler: scheduler,
            ruleEngine: ReminderRuleEngine(calendar: calendar),
            calendar: calendar,
            clock: {
                self.calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
            }
        )
        let created = try await service.create(
            title: "Custom",
            eventDate: calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!,
            includeTime: true,
            eventTime: calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!,
            note: nil,
            rules: [
                .exactAtEvent(),
                .beforeEvent(value: 2, unit: .week)
            ],
            timeZoneIdentifier: calendar.timeZone.identifier
        )
        let form = ReminderScheduleFormModel()
        form.load(from: created.reminder, calendar: calendar)
        form.remindOneDayBefore = true // unrelated field change
        let rules = try form.buildRules(eventDate: created.reminder.eventDate, calendar: calendar)
        var edited = created.reminder
        edited.rules = rules
        _ = try await service.update(edited)
        await service.reconcileAllNotifications()

        let stored = try XCTUnwrap(service.reminder(id: created.reminder.id))
        XCTAssertTrue(stored.rules.contains {
            $0.ruleType == .beforeEvent && $0.offsetValue == 2 && $0.offsetUnit == .week
        })
        XCTAssertTrue(stored.rules.contains {
            $0.ruleType == .beforeEvent && $0.offsetValue == 1 && $0.offsetUnit == .day
        })
    }
}

@MainActor
final class ReminderDateWindowTimezoneTests: XCTestCase {
    /// TC-WINDOW-TZ-001 Stored timezone controls window display.
    /// TC-WINDOW-TZ-002 Stored timezone controls window editing/save.
    /// TC-WINDOW-TZ-003 Stored timezone controls recurrence generation.
    /// TC-WINDOW-TZ-004 Device timezone change does not shift stored window dates.
    func testStoredTimezoneControlsWindowAcrossEditAndGeneration() throws {
        let ny = TimeZone(identifier: "America/New_York")!
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = ny

        let window = ReminderDateWindow(
            startDate: DateComponents(year: 2026, month: 9, day: 1),
            endDate: DateComponents(year: 2026, month: 9, day: 30)
        )
        let reminder = Reminder(
            title: "NY Window",
            eventDate: DateComponents(year: 2026, month: 9, day: 1),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: "America/New_York",
            rules: [.recurring(.weekly(weekdays: [2]), window: window)]
        )

        let form = ReminderScheduleFormModel()
        form.load(from: reminder, calendar: nyCalendar)
        XCTAssertTrue(form.useDateWindow)

        // Wall-calendar day in NY must be Sep 1 / Sep 30 even if device is Kolkata.
        let startComps = nyCalendar.dateComponents([.year, .month, .day], from: form.windowStart)
        let endComps = nyCalendar.dateComponents([.year, .month, .day], from: form.windowEnd)
        XCTAssertEqual(startComps.year, 2026)
        XCTAssertEqual(startComps.month, 9)
        XCTAssertEqual(startComps.day, 1)
        XCTAssertEqual(endComps.day, 30)

        // Device TZ Kolkata must not be used when saving window components.
        var kolkata = Calendar(identifier: .gregorian)
        kolkata.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let rebuilt = try form.buildRules(eventDate: reminder.eventDate, calendar: nyCalendar)
        let savedWindow = rebuilt.first(where: { $0.ruleType == .recurring })?.dateWindow
        XCTAssertEqual(savedWindow?.startDate.year, 2026)
        XCTAssertEqual(savedWindow?.startDate.month, 9)
        XCTAssertEqual(savedWindow?.startDate.day, 1)
        XCTAssertEqual(savedWindow?.endDate.day, 30)

        // Wrong calendar (device TZ) would shift near midnight boundaries; noon anchors avoid that,
        // and authoritative save still uses reminder calendar.
        let wrongSave = try form.buildRules(eventDate: reminder.eventDate, calendar: kolkata)
        // Even if UI Date values were interpreted in Kolkata, Sep 1 noon NY is still Sep 1 in Kolkata.
        XCTAssertEqual(wrongSave.first(where: { $0.ruleType == .recurring })?.dateWindow?.startDate.day, 1)

        let engine = ReminderRuleEngine(calendar: nyCalendar)
        let now = nyCalendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8))!
        let fires = engine.occurrences(for: reminder, now: now).map(\.fireAt)
        XCTAssertFalse(fires.isEmpty)
        for fire in fires {
            let day = nyCalendar.component(.day, from: fire)
            let month = nyCalendar.component(.month, from: fire)
            XCTAssertEqual(month, 9)
            XCTAssertGreaterThanOrEqual(day, 1)
            XCTAssertLessThanOrEqual(day, 30)
        }

        // Simulate device TZ change: reload with NY calendar still yields Sep 1–30.
        let formAfterDeviceChange = ReminderScheduleFormModel()
        formAfterDeviceChange.load(from: reminder, calendar: nyCalendar)
        let reloadedStart = nyCalendar.dateComponents(
            [.year, .month, .day],
            from: formAfterDeviceChange.windowStart
        )
        XCTAssertEqual(reloadedStart.day, 1)
        XCTAssertEqual(reloadedStart.month, 9)
    }

    @MainActor
    func testWindowTimezoneHonoredWhenScheduling() async throws {
        let ny = TimeZone(identifier: "America/New_York")!
        var nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = ny
        // Service uses a Kolkata "device" calendar; reminder stores America/New_York.
        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!

        let scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        let repo = InMemoryReminderRepository()
        let service = ReminderService(
            repository: repo,
            notificationScheduler: scheduler,
            ruleEngine: ReminderRuleEngine(calendar: deviceCalendar),
            calendar: deviceCalendar,
            clock: {
                nyCalendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 8))!
            }
        )

        let window = ReminderDateWindow(
            startDate: DateComponents(year: 2026, month: 9, day: 1),
            endDate: DateComponents(year: 2026, month: 9, day: 30)
        )
        let created = try await service.create(
            title: "NY Window",
            eventDate: nyCalendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!,
            includeTime: true,
            eventTime: nyCalendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 9))!,
            note: nil,
            rules: [.recurring(.daily(), window: window)],
            timeZoneIdentifier: "America/New_York"
        )

        XCTAssertFalse(scheduler.scheduled.isEmpty)
        for request in scheduler.scheduled {
            let day = nyCalendar.component(.day, from: request.fireAt)
            let month = nyCalendar.component(.month, from: request.fireAt)
            XCTAssertEqual(month, 9)
            XCTAssertGreaterThanOrEqual(day, 1)
            XCTAssertLessThanOrEqual(day, 30)
            XCTAssertEqual(request.timeZoneIdentifier, "America/New_York")
        }
        XCTAssertEqual(created.reminder.timeZoneIdentifier, "America/New_York")
    }
}

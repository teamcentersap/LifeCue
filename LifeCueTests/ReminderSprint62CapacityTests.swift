import XCTest
@testable import LifeCue

@MainActor
final class ReminderActiveLimitTests: XCTestCase {
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

    private func makeService(
        policy: ReminderSchedulingPolicy = .default
    ) -> (ReminderService, InMemoryReminderRepository, FakeNotificationScheduler) {
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        let repo = InMemoryReminderRepository()
        let service = ReminderService(
            repository: repo,
            notificationScheduler: scheduler,
            ruleEngine: ReminderRuleEngine(policy: policy, calendar: calendar),
            calendar: calendar,
            clock: { self.now }
        )
        return (service, repo, scheduler)
    }

    private func createActive(
        _ service: ReminderService,
        title: String,
        dayOffset: Int = 1
    ) async throws -> Reminder {
        let event = calendar.date(byAdding: .day, value: dayOffset, to: now)!
        return try await service.create(
            title: title,
            eventDate: event,
            includeTime: true,
            eventTime: event,
            note: nil,
            rules: [.exactAtEvent()],
            timeZoneIdentifier: timeZone.identifier
        ).reminder
    }

    private func fillActive(
        _ service: ReminderService,
        count: Int
    ) async throws {
        for index in 0..<count {
            _ = try await createActive(service, title: "R\(index)", dayOffset: index + 1)
        }
    }

    /// TC-LIMIT-001 59 active → create succeeds
    func testCreateSucceedsAt59Active() async throws {
        let (service, _, _) = makeService()
        try await fillActive(service, count: 59)
        let created = try await createActive(service, title: "Sixtieth", dayOffset: 100)
        XCTAssertEqual(try service.allReminders().filter { $0.status == .active }.count, 60)
        XCTAssertEqual(created.title, "Sixtieth")
    }

    /// TC-LIMIT-002 60th create succeeds (from 59)
    func testCreateSucceedsReachingExactly60() async throws {
        let (service, _, _) = makeService()
        try await fillActive(service, count: 59)
        _ = try await createActive(service, title: "AtLimit", dayOffset: 100)
        XCTAssertEqual(try service.allReminders().filter { $0.status == .active }.count, 60)
    }

    /// TC-LIMIT-003 61st create fails
    func testCreateFailsAt61st() async throws {
        let (service, _, _) = makeService()
        try await fillActive(service, count: 60)
        do {
            _ = try await createActive(service, title: "Over", dayOffset: 200)
            XCTFail("Expected active reminder limit error")
        } catch let error as ReminderValidationError {
            XCTAssertEqual(error, .activeReminderLimitReached(limit: 60))
            XCTAssertEqual(
                error.errorDescription,
                "You've reached the limit of 60 active reminders. Complete or delete an existing reminder to add a new one."
            )
        }
        XCTAssertEqual(try service.allReminders().filter { $0.status == .active }.count, 60)
        XCTAssertEqual(try service.allReminders().count, 60)
    }

    /// TC-LIMIT-004 Completed does not count
    func testCompletedDoesNotCountTowardLimit() async throws {
        let (service, _, _) = makeService()
        try await fillActive(service, count: 59)
        let extra = try await createActive(service, title: "ToComplete", dayOffset: 90)
        _ = try await service.complete(id: extra.id)
        XCTAssertEqual(try service.allReminders().filter { $0.status == .active }.count, 59)
        _ = try await createActive(service, title: "AfterComplete", dayOffset: 91)
        XCTAssertEqual(try service.allReminders().filter { $0.status == .active }.count, 60)
    }

    /// TC-LIMIT-005 Deleted does not count
    func testDeletedDoesNotCountTowardLimit() async throws {
        let (service, _, _) = makeService()
        try await fillActive(service, count: 60)
        let victim = try XCTUnwrap(try service.allReminders().first)
        try await service.delete(id: victim.id)
        _ = try await createActive(service, title: "AfterDelete", dayOffset: 120)
        XCTAssertEqual(try service.allReminders().filter { $0.status == .active }.count, 60)
    }

    /// TC-LIMIT-006 Completing one of 60 allows a new reminder
    func testCompletingOneOf60AllowsCreate() async throws {
        let (service, _, _) = makeService()
        try await fillActive(service, count: 60)
        let first = try XCTUnwrap(try service.allReminders().first)
        _ = try await service.complete(id: first.id)
        _ = try await createActive(service, title: "Replacement", dayOffset: 130)
        XCTAssertEqual(try service.allReminders().filter { $0.status == .active }.count, 60)
    }

    /// TC-LIMIT-007 Deleting one of 60 allows a new reminder
    func testDeletingOneOf60AllowsCreate() async throws {
        let (service, _, _) = makeService()
        try await fillActive(service, count: 60)
        let first = try XCTUnwrap(try service.allReminders().first)
        try await service.delete(id: first.id)
        _ = try await createActive(service, title: "Replacement", dayOffset: 140)
        XCTAssertEqual(try service.allReminders().filter { $0.status == .active }.count, 60)
    }

    /// TC-LIMIT-008 Editing at 60 remains allowed
    func testEditAllowedAt60Active() async throws {
        let (service, _, _) = makeService()
        try await fillActive(service, count: 60)
        var edited = try XCTUnwrap(try service.allReminders().first)
        edited.title = "Edited At Cap"
        let result = try await service.update(edited)
        XCTAssertEqual(result.reminder.title, "Edited At Cap")
        XCTAssertEqual(try service.allReminders().filter { $0.status == .active }.count, 60)
    }

    /// TC-LIMIT-009 Screenshot-created reminder respects the same limit
    func testScreenshotCreateRespectsLimit() async throws {
        let (service, _, _) = makeService()
        try await fillActive(service, count: 60)
        let draft = ReminderDraft(
            title: "From Screenshot",
            titleWasFallback: false,
            dateState: .resolved(DateComponents(year: 2026, month: 9, day: 18)),
            timeState: .resolved(DateComponents(hour: 16, minute: 0)),
            note: nil,
            personName: nil,
            contextName: nil,
            personID: nil,
            contextID: nil,
            proposedRecurrence: nil,
            timeZoneIdentifier: timeZone.identifier,
            localeIdentifier: "en_GB",
            sourceText: "From Screenshot\n18 September 2026"
        )
        do {
            _ = try await service.createFromConfirmedDraft(draft)
            XCTFail("Expected limit error from draft create")
        } catch let error as ReminderValidationError {
            XCTAssertEqual(error, .activeReminderLimitReached(limit: 60))
        }
        XCTAssertEqual(try service.allReminders().filter { $0.status == .active }.count, 60)
    }

    /// TC-LIMIT-010 Limit validation is in the service/domain path
    func testLimitEnforcedInServiceNotOnlyUI() async throws {
        let (service, repo, _) = makeService()
        try await fillActive(service, count: 60)
        // Direct service call (no UI) must reject.
        await XCTAssertThrowsErrorAsync(
            try await service.create(
                title: "No UI",
                eventDate: now,
                includeTime: false,
                eventTime: nil,
                note: nil,
                rules: [.exactAtEvent()],
                timeZoneIdentifier: timeZone.identifier
            )
        ) { error in
            XCTAssertEqual(error as? ReminderValidationError, .activeReminderLimitReached(limit: 60))
        }
        XCTAssertEqual(try repo.fetchAll().count, 60)
    }
}

@MainActor
final class ReminderNotificationBudgetTests: XCTestCase {
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

    private func tightPolicy(budget: Int, perReminder: Int = 16) -> ReminderSchedulingPolicy {
        ReminderSchedulingPolicy(
            defaultTimeOfDay: DateComponents(hour: 9, minute: 0),
            maxOccurrencesPerReminder: perReminder,
            horizonDays: 800,
            maxActiveReminders: 60,
            maxPendingNotifications: budget
        )
    }

    private func makeService(
        policy: ReminderSchedulingPolicy
    ) -> (ReminderService, InMemoryReminderRepository, FakeNotificationScheduler) {
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        let repo = InMemoryReminderRepository()
        let service = ReminderService(
            repository: repo,
            notificationScheduler: scheduler,
            ruleEngine: ReminderRuleEngine(policy: policy, calendar: calendar),
            calendar: calendar,
            clock: { self.now }
        )
        return (service, repo, scheduler)
    }

    /// TC-NOTIF-BUDGET-001 Never intentionally exceeds configured budget
    func testSchedulerNeverExceedsBudget() async throws {
        let budget = 5
        let (service, _, scheduler) = makeService(policy: tightPolicy(budget: budget))
        // Three daily recurrings each desire 16 → 48 desired, budget 5.
        for index in 0..<3 {
            let event = calendar.date(byAdding: .day, value: index, to: now)!
            _ = try await service.create(
                title: "Daily\(index)",
                eventDate: event,
                includeTime: true,
                eventTime: calendar.date(from: DateComponents(year: 2026, month: 8, day: 10 + index, hour: 9))!,
                note: nil,
                rules: [.recurring(.daily())],
                timeZoneIdentifier: timeZone.identifier
            )
        }
        await service.reconcileAllNotifications()
        XCTAssertLessThanOrEqual(scheduler.scheduled.count, budget)
        XCTAssertEqual(scheduler.scheduled.count, budget)
    }

    /// TC-NOTIF-BUDGET-002 Nearest future occurrences are prioritized
    func testNearestFutureOccurrencesPrioritized() async throws {
        let budget = 3
        let (service, _, scheduler) = makeService(policy: tightPolicy(budget: budget, perReminder: 8))

        let far = calendar.date(from: DateComponents(year: 2026, month: 12, day: 1, hour: 9))!
        let near = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9))!

        _ = try await service.create(
            title: "Far",
            eventDate: far,
            includeTime: true,
            eventTime: far,
            note: nil,
            rules: [.exactAtEvent()],
            timeZoneIdentifier: timeZone.identifier
        )
        _ = try await service.create(
            title: "NearDaily",
            eventDate: near,
            includeTime: true,
            eventTime: near,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )

        await service.reconcileAllNotifications()
        XCTAssertEqual(scheduler.scheduled.count, budget)
        let titles = Set(scheduler.scheduled.map(\.title))
        XCTAssertTrue(titles.contains("NearDaily"))
        XCTAssertFalse(titles.contains("Far"), "Farther one-shot must yield to nearer daily fires")
        let fires = scheduler.scheduled.map(\.fireAt).sorted()
        XCTAssertEqual(fires, Array(fires.prefix(budget)))
        // All scheduled fires should be the earliest possible among desired set.
        XCTAssertTrue(fires.allSatisfy { $0 < far })
    }

    /// TC-NOTIF-BUDGET-003 Recurring remains eligible for later replenishment
    func testRecurringRemainsEligibleForLaterReplenishment() async throws {
        var current = now!
        let budget = 4
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        let repo = InMemoryReminderRepository()
        let policy = tightPolicy(budget: budget, perReminder: 16)
        let service = ReminderService(
            repository: repo,
            notificationScheduler: scheduler,
            ruleEngine: ReminderRuleEngine(policy: policy, calendar: calendar),
            calendar: calendar,
            clock: { current }
        )

        let event = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9))!
        let created = try await service.create(
            title: "Daily",
            eventDate: event,
            includeTime: true,
            eventTime: event,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        await service.reconcileAllNotifications()
        let firstBatch = Set(scheduler.scheduled.map(\.identifier))
        XCTAssertEqual(firstBatch.count, budget)

        // Consume capacity window and advance clock; replenish should schedule later days.
        current = calendar.date(byAdding: .day, value: 10, to: now)!
        scheduler.reset()
        scheduler.status = .authorized
        await service.reconcileAllNotifications()

        let second = scheduler.scheduled.filter { $0.identifier.contains(created.reminder.id.uuidString) }
        XCTAssertEqual(second.count, budget)
        XCTAssertTrue(second.allSatisfy { $0.fireAt > current })
        XCTAssertTrue(Set(second.map(\.identifier)).isDisjoint(with: firstBatch))
    }

    /// TC-NOTIF-BUDGET-004 Reconciliation does not duplicate notifications
    func testReconcileDoesNotDuplicate() async throws {
        let (service, _, scheduler) = makeService(policy: tightPolicy(budget: 10))
        let event = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 9))!
        _ = try await service.create(
            title: "Daily",
            eventDate: event,
            includeTime: true,
            eventTime: event,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        await service.reconcileAllNotifications()
        let afterFirst = scheduler.scheduled.count
        let ids = Set(scheduler.scheduled.map(\.identifier))
        await service.reconcileAllNotifications()
        await service.reconcileAllNotifications()
        XCTAssertEqual(scheduler.scheduled.count, afterFirst)
        XCTAssertEqual(Set(scheduler.scheduled.map(\.identifier)).count, ids.count)
    }

    /// TC-NOTIF-BUDGET-005 Completed/deleted free notification capacity
    func testCompletedAndDeletedFreeCapacity() async throws {
        let budget = 4
        let (service, _, scheduler) = makeService(policy: tightPolicy(budget: budget, perReminder: 4))

        // Fill budget with near daily reminder.
        let near = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 9))!
        let nearCreated = try await service.create(
            title: "Near",
            eventDate: near,
            includeTime: true,
            eventTime: near,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        let far = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 9))!
        _ = try await service.create(
            title: "Far",
            eventDate: far,
            includeTime: true,
            eventTime: far,
            note: nil,
            rules: [.exactAtEvent()],
            timeZoneIdentifier: timeZone.identifier
        )
        await service.reconcileAllNotifications()
        XCTAssertEqual(scheduler.scheduled.count, budget)
        XCTAssertTrue(scheduler.scheduled.allSatisfy { $0.title == "Near" })

        _ = try await service.complete(id: nearCreated.reminder.id)
        await service.reconcileAllNotifications()
        XCTAssertTrue(scheduler.scheduled.contains { $0.title == "Far" })
        XCTAssertFalse(scheduler.scheduled.contains { $0.title == "Near" })
        XCTAssertLessThanOrEqual(scheduler.scheduled.count, budget)

        let farReminder = try XCTUnwrap(try service.allReminders().first { $0.title == "Far" })
        try await service.delete(id: farReminder.id)
        await service.reconcileAllNotifications()
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }
}

/// Async-friendly XCTAssertThrowsError for service-path limit checks.
@MainActor
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath,
    line: UInt = #line,
    _ errorHandler: (Error) -> Void = { _ in }
) async {
    do {
        _ = try await expression()
        XCTFail(message().isEmpty ? "Expected error to be thrown" : message(), file: file, line: line)
    } catch {
        errorHandler(error)
    }
}

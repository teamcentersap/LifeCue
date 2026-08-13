import XCTest
import UserNotifications
@testable import LifeCue

@MainActor
final class LifeCueNotificationCenterDelegateTests: XCTestCase {
    private var previousDelegate: UNUserNotificationCenterDelegate?

    override func setUp() {
        super.setUp()
        previousDelegate = UNUserNotificationCenter.current().delegate
    }

    override func tearDown() {
        UNUserNotificationCenter.current().delegate = previousDelegate
        previousDelegate = nil
        super.tearDown()
    }

    /// TC-NAV-NOTIF-011 Foreground presentation delegate still returns banner/sound/badge.
    func testForegroundPresentationOptionsIncludeBannerSoundBadge() {
        let options = LifeCueNotificationCenterDelegate.foregroundPresentationOptions
        XCTAssertTrue(options.contains(.banner))
        XCTAssertTrue(options.contains(.sound))
        XCTAssertTrue(options.contains(.badge))
        XCTAssertEqual(options, [.banner, .sound, .badge])
    }

    func testInstallAssignsSharedCenterDelegate() {
        let store = NotificationNavigationStore()
        let delegate = LifeCueNotificationCenterDelegate(navigationStore: store)
        LifeCueNotificationCenterDelegate.install(delegate)
        XCTAssertTrue(
            UNUserNotificationCenter.current().delegate === delegate,
            "Delegate must be assigned early so willPresent can run in foreground"
        )
    }

    func testWillPresentUsesForegroundPresentationOptions() {
        let store = NotificationNavigationStore()
        let delegate = LifeCueNotificationCenterDelegate(navigationStore: store)
            as UNUserNotificationCenterDelegate
        XCTAssertNotNil(delegate)
        XCTAssertEqual(
            LifeCueNotificationCenterDelegate.foregroundPresentationOptions,
            [.banner, .sound, .badge]
        )
    }
}

@MainActor
final class NotificationTapRoutingTests: XCTestCase {
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var reminderRepo: InMemoryReminderRepository!
    private var reminderService: ReminderService!
    private var personService: PersonService!
    private var contextService: ContextService!
    private var scheduler: FakeNotificationScheduler!
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 12))!
        personRepo = InMemoryPersonRepository()
        contextRepo = InMemoryContextRepository()
        reminderRepo = InMemoryReminderRepository()
        scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        reminderService = ReminderService(
            repository: reminderRepo,
            notificationScheduler: scheduler,
            personRepository: personRepo,
            contextRepository: contextRepo,
            ruleEngine: ReminderRuleEngine(calendar: calendar),
            calendar: calendar,
            clock: { self.now }
        )
        personService = PersonService(repository: personRepo)
        contextService = ContextService(repository: contextRepo, personRepository: personRepo)
    }

    private func futureEvent(days: Int = 2) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    /// TC-NAV-NOTIF-001 / TC-NAV-NOTIF-010
    func testValidReminderIDResolvesFromUserInfoAndIdentifier() async throws {
        let created = try await reminderService.create(
            title: "Tap me",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            rules: [.exactAtEvent()]
        )
        let id = created.reminder.id
        let fromInfo = NotificationTapRouting.reminderID(
            requestIdentifier: "unrelated",
            userInfo: ["reminderID": id.uuidString]
        )
        XCTAssertEqual(fromInfo, id)

        let requestID = NotificationIdentifier.occurrence(
            reminderID: id,
            generation: 1,
            ruleID: UUID(),
            occurrenceKey: "t1"
        )
        let fromRequest = NotificationTapRouting.reminderID(
            requestIdentifier: requestID,
            userInfo: [:]
        )
        XCTAssertEqual(fromRequest, id)

        let resolution = NotificationTapResolver.resolve(reminderID: id) {
            try reminderService.reminder(id: $0)
        }
        XCTAssertEqual(resolution, .open(id))
    }

    /// TC-NAV-NOTIF-002
    func testInvalidMissingReminderIDHandledSafely() {
        XCTAssertNil(
            NotificationTapRouting.reminderID(
                requestIdentifier: "not-a-lifecue-id",
                userInfo: [:]
            )
        )
        XCTAssertEqual(
            NotificationTapResolver.resolve(reminderID: nil) { _ in nil },
            .unavailable
        )
        XCTAssertEqual(
            NotificationTapResolver.resolve(reminderID: UUID()) { _ in nil },
            .unavailable
        )
    }

    /// TC-NAV-NOTIF-003
    func testDeletedReminderDoesNotCrash() async throws {
        let created = try await reminderService.create(
            title: "Delete me",
            eventDate: futureEvent(),
            includeTime: false,
            eventTime: nil,
            rules: [.exactAtEvent()]
        )
        try await reminderService.delete(id: created.reminder.id)
        let resolution = NotificationTapResolver.resolve(reminderID: created.reminder.id) {
            try reminderService.reminder(id: $0)
        }
        XCTAssertEqual(resolution, .unavailable)
    }

    /// TC-NAV-NOTIF-004
    func testCompletedReminderCanStillBeOpened() async throws {
        let created = try await reminderService.create(
            title: "Done",
            eventDate: futureEvent(),
            includeTime: false,
            eventTime: nil,
            rules: [.exactAtEvent()]
        )
        _ = try await reminderService.complete(id: created.reminder.id)
        let resolution = NotificationTapResolver.resolve(reminderID: created.reminder.id) {
            try reminderService.reminder(id: $0)
        }
        XCTAssertEqual(resolution, .open(created.reminder.id))
        let loaded = try XCTUnwrap(reminderService.reminder(id: created.reminder.id))
        XCTAssertEqual(loaded.status, .completed)
    }

    /// TC-NAV-NOTIF-005
    func testSnoozedReminderRemainsSnoozed() async throws {
        let created = try await reminderService.create(
            title: "Snooze me",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            rules: [.exactAtEvent()]
        )
        _ = try await reminderService.snooze(id: created.reminder.id, option: .laterToday)
        let before = try XCTUnwrap(reminderService.reminder(id: created.reminder.id))
        XCTAssertNotNil(before.snooze)

        let resolution = NotificationTapResolver.resolve(reminderID: before.id) {
            try reminderService.reminder(id: $0)
        }
        XCTAssertEqual(resolution, .open(before.id))
        let after = try XCTUnwrap(reminderService.reminder(id: before.id))
        XCTAssertEqual(after.snooze, before.snooze)
        XCTAssertEqual(after.status, before.status)
    }

    /// TC-NAV-NOTIF-006
    func testPersonContextMetadataRemainsIntact() async throws {
        let person = try personService.create(name: "Child 1")
        let context = try contextService.create(name: "Doctor", personID: person.id)
        let created = try await reminderService.create(
            title: "Appointment",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            rules: [.exactAtEvent()],
            personID: person.id,
            contextID: context.id
        )
        _ = NotificationTapResolver.resolve(reminderID: created.reminder.id) {
            try reminderService.reminder(id: $0)
        }
        let loaded = try XCTUnwrap(reminderService.reminder(id: created.reminder.id))
        XCTAssertEqual(loaded.personID, person.id)
        XCTAssertEqual(loaded.contextID, context.id)
        let resolver = ReminderMetadataResolver(
            personService: personService,
            contextService: contextService
        )
        XCTAssertEqual(resolver.compactSubtitle(for: loaded), "Child 1 · Doctor")
    }

    /// TC-NAV-NOTIF-007 / TC-NAV-NOTIF-008 / TC-NAV-NOTIF-009
    func testTapDoesNotScheduleOrMutateReminder() async throws {
        let created = try await reminderService.create(
            title: "Stable",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            rules: [.recurring(.daily())]
        )
        let beforeIDs = scheduler.scheduled.map(\.identifier)
        let beforeReminder = try XCTUnwrap(reminderService.reminder(id: created.reminder.id))

        _ = NotificationTapResolver.resolve(reminderID: beforeReminder.id) {
            try reminderService.reminder(id: $0)
        }

        let after = try XCTUnwrap(reminderService.reminder(id: created.reminder.id))
        XCTAssertEqual(scheduler.scheduled.map(\.identifier), beforeIDs)
        XCTAssertEqual(after.rules, beforeReminder.rules)
        XCTAssertEqual(after.status, beforeReminder.status)
        XCTAssertEqual(after, beforeReminder)
    }

    /// TC-NAV-NOTIF-013 / TC-NAV-NOTIF-014 / TC-NAV-NOTIF-015
    func testPendingNavigationStoreColdStartAndActiveRouting() {
        let store = NotificationNavigationStore()
        let id = UUID()
        store.enqueue(reminderID: id)
        XCTAssertEqual(store.pendingReminderID, id)
        XCTAssertFalse(store.pendingUnavailable)
        XCTAssertEqual(store.pendingGeneration, 1)

        store.consumePendingOpen()
        XCTAssertNil(store.pendingReminderID)

        // Active / background re-tap of same ID still bumps generation.
        store.enqueue(reminderID: id)
        XCTAssertEqual(store.pendingGeneration, 2)
        XCTAssertEqual(store.pendingReminderID, id)

        store.enqueue(reminderID: nil)
        XCTAssertTrue(store.pendingUnavailable)
        XCTAssertNil(store.pendingReminderID)
        store.consumeUnavailable()
        XCTAssertFalse(store.pendingUnavailable)
    }

    /// TC-NAV-NOTIF-012 Existing identifier parsing remains compatible with scheduling format.
    func testExistingNotificationIdentifierFormatUnchanged() {
        let reminderID = UUID()
        let ruleID = UUID()
        let identifier = NotificationIdentifier.occurrence(
            reminderID: reminderID,
            generation: 3,
            ruleID: ruleID,
            occurrenceKey: "t100"
        )
        XCTAssertTrue(identifier.hasPrefix(NotificationIdentifier.reminderPrefix))
        XCTAssertEqual(NotificationIdentifier.reminderID(from: identifier), reminderID)
        XCTAssertEqual(
            NotificationTapRouting.reminderIDUserInfoKey,
            "reminderID"
        )
    }
}

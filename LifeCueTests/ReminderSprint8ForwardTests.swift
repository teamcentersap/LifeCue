import XCTest
@testable import LifeCue

final class ReminderForwardFormatterTests: XCTestCase {
    private var calendar: Calendar!
    private var nyCalendar: Calendar!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        nyCalendar = Calendar(identifier: .gregorian)
        nyCalendar.timeZone = TimeZone(identifier: "America/New_York")!
    }

    private func oneShot(
        title: String = "Doctor appointment",
        date: DateComponents = DateComponents(year: 2026, month: 9, day: 20),
        time: DateComponents? = DateComponents(hour: 16, minute: 0),
        zone: String = "Asia/Kolkata",
        note: String? = nil,
        personID: UUID? = nil,
        contextID: UUID? = nil
    ) -> Reminder {
        Reminder(
            title: title,
            eventDate: date,
            eventTime: time,
            timeZoneIdentifier: zone,
            note: note,
            personID: personID,
            contextID: contextID,
            rules: [.exactAtEvent()]
        )
    }

    /// TC-FORWARD-001 Basic title/date
    func testBasicTitleAndDate() {
        let text = ReminderForwardFormatter.makeText(for: oneShot(time: nil))
        XCTAssertTrue(text.hasPrefix("Doctor appointment"))
        XCTAssertTrue(text.contains("Date: 20 September 2026"))
    }

    /// TC-FORWARD-002 Time included
    func testIncludesTime() {
        let text = ReminderForwardFormatter.makeText(for: oneShot())
        XCTAssertTrue(text.contains("Time:"))
        XCTAssertTrue(text.contains("4:00") || text.contains("16:00"))
    }

    /// TC-FORWARD-003 Date-only omits time
    func testDateOnlyOmitsTime() {
        let text = ReminderForwardFormatter.makeText(for: oneShot(time: nil))
        XCTAssertFalse(text.contains("Time:"))
    }

    /// TC-FORWARD-004 Person included
    func testPersonIncluded() {
        let text = ReminderForwardFormatter.makeText(
            for: oneShot(),
            personName: "Child 1"
        )
        XCTAssertTrue(text.contains("For: Child 1"))
    }

    /// TC-FORWARD-005 Context included
    func testContextIncluded() {
        let text = ReminderForwardFormatter.makeText(
            for: oneShot(),
            contextName: "Doctor"
        )
        XCTAssertTrue(text.contains("Context: Doctor"))
    }

    /// TC-FORWARD-006 Person/context omitted when nil
    func testOmitsNilPersonAndContext() {
        let text = ReminderForwardFormatter.makeText(for: oneShot())
        XCTAssertFalse(text.contains("For:"))
        XCTAssertFalse(text.contains("Context:"))
        XCTAssertFalse(text.contains("For: —"))
        XCTAssertFalse(text.contains("Context: —"))
    }

    /// TC-FORWARD-007 Note included
    func testNoteIncluded() {
        let text = ReminderForwardFormatter.makeText(
            for: oneShot(note: "Bring previous reports.")
        )
        XCTAssertTrue(text.contains("Note:"))
        XCTAssertTrue(text.contains("Bring previous reports."))
    }

    /// TC-FORWARD-008 Empty note omitted
    func testEmptyNoteOmitted() {
        let text = ReminderForwardFormatter.makeText(for: oneShot(note: "   "))
        XCTAssertFalse(text.contains("Note:"))
    }

    /// TC-FORWARD-009 Archived person representation
    func testArchivedPerson() {
        let text = ReminderForwardFormatter.makeText(
            for: oneShot(),
            personName: "Child 1 (archived)"
        )
        XCTAssertTrue(text.contains("For: Child 1 (archived)"))
    }

    /// TC-FORWARD-010 Archived context representation
    func testArchivedContext() {
        let text = ReminderForwardFormatter.makeText(
            for: oneShot(),
            contextName: "Doctor (archived)"
        )
        XCTAssertTrue(text.contains("Context: Doctor (archived)"))
    }

    /// TC-FORWARD-011 Stored timezone used
    func testStoredTimezoneUsed() {
        // 20 Sep 2026 in America/New_York must not shift to 19/21 because device is Kolkata.
        let reminder = oneShot(
            date: DateComponents(year: 2026, month: 9, day: 20),
            time: DateComponents(hour: 16, minute: 0),
            zone: "America/New_York"
        )
        let text = ReminderForwardFormatter.makeText(for: reminder)
        XCTAssertTrue(text.contains("Date: 20 September 2026"))
        let time = ReminderDisplayFormatter.timeString(for: reminder)
        XCTAssertNotNil(time)
        XCTAssertTrue(text.contains("Time: \(time!)"))
    }

    /// TC-FORWARD-012 Daily recurrence
    func testDailyRecurrence() {
        let reminder = Reminder(
            title: "Daily medicine reminder",
            eventDate: DateComponents(year: 2026, month: 8, day: 10),
            eventTime: DateComponents(hour: 8, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            note: "Take after breakfast.",
            personID: nil,
            rules: [.recurring(.daily())]
        )
        let text = ReminderForwardFormatter.makeText(for: reminder, personName: "Child 1")
        XCTAssertTrue(text.contains("Every day"))
        XCTAssertTrue(text.contains("at "))
        XCTAssertTrue(text.contains("For: Child 1"))
        XCTAssertTrue(text.contains("Take after breakfast."))
        XCTAssertFalse(text.contains("Date:"))
    }

    /// TC-FORWARD-013 Weekly
    func testWeeklyRecurrence() {
        let reminder = Reminder(
            title: "Football",
            eventDate: DateComponents(year: 2026, month: 9, day: 7),
            eventTime: DateComponents(hour: 16, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.recurring(.weekly(weekdays: [2]))]
        )
        let text = ReminderForwardFormatter.makeText(for: reminder)
        XCTAssertTrue(text.contains("Every Monday"))
    }

    /// TC-FORWARD-014 Monthly
    func testMonthlyRecurrence() {
        let reminder = Reminder(
            title: "Rent",
            eventDate: DateComponents(year: 2026, month: 9, day: 1),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.recurring(.monthly(dayOfMonth: 1))]
        )
        let text = ReminderForwardFormatter.makeText(for: reminder)
        XCTAssertTrue(text.contains("Every month on the 1"))
    }

    /// TC-FORWARD-015 Yearly
    func testYearlyRecurrence() {
        let reminder = Reminder(
            title: "Doctor follow-up",
            eventDate: DateComponents(year: 2026, month: 9, day: 20),
            eventTime: DateComponents(hour: 16, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.recurring(.yearly())]
        )
        let text = ReminderForwardFormatter.makeText(
            for: reminder,
            personName: "Child 1",
            contextName: "Doctor"
        )
        XCTAssertTrue(text.contains("Every year on September 20"))
        XCTAssertTrue(text.contains("For: Child 1"))
        XCTAssertTrue(text.contains("Context: Doctor"))
    }

    /// TC-FORWARD-016 Date window
    func testDateWindow() {
        let window = ReminderDateWindow(
            startDate: DateComponents(year: 2026, month: 9, day: 1),
            endDate: DateComponents(year: 2026, month: 11, day: 30)
        )
        let reminder = Reminder(
            title: "Class",
            eventDate: DateComponents(year: 2026, month: 9, day: 1),
            eventTime: DateComponents(hour: 16, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.recurring(.weekly(weekdays: [2]), window: window)]
        )
        let text = ReminderForwardFormatter.makeText(for: reminder)
        XCTAssertTrue(text.contains("Every Monday"))
        XCTAssertTrue(text.contains("From: 1 September 2026"))
        XCTAssertTrue(text.contains("Until: 30 November 2026"))
    }

    /// No internal IDs in output
    func testOmitsInternalIDs() {
        let id = UUID()
        let reminder = oneShot(personID: id, contextID: id)
        let text = ReminderForwardFormatter.makeText(
            for: reminder,
            personName: "Me",
            contextName: "Home"
        )
        XCTAssertFalse(text.contains(id.uuidString))
        XCTAssertFalse(text.contains("timeZoneIdentifier"))
        XCTAssertFalse(text.contains("America/"))
        XCTAssertFalse(text.contains("Asia/"))
    }
}

@MainActor
final class ReminderForwardLifecycleTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!
    private var reminderRepo: InMemoryReminderRepository!
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var scheduler: FakeNotificationScheduler!
    private var service: ReminderService!
    private var people: PersonService!
    private var contexts: ContextService!
    private var sharing: FakeForwardSharingService!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        reminderRepo = InMemoryReminderRepository()
        personRepo = InMemoryPersonRepository()
        contextRepo = InMemoryContextRepository()
        scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        service = ReminderService(
            repository: reminderRepo,
            notificationScheduler: scheduler,
            personRepository: personRepo,
            contextRepository: contextRepo,
            ruleEngine: ReminderRuleEngine(calendar: calendar),
            calendar: calendar,
            clock: { self.now }
        )
        people = PersonService(repository: personRepo)
        contexts = ContextService(repository: contextRepo, personRepository: personRepo)
        sharing = FakeForwardSharingService()
    }

    private func future() -> Date {
        calendar.date(byAdding: .day, value: 5, to: now)!
    }

    /// TC-FORWARD-017…020 Forward does not mutate reminder / rules / snooze / notifications
    func testForwardDoesNotMutateReminderOrNotifications() async throws {
        let created = try await service.create(
            title: "Call",
            eventDate: future(),
            includeTime: true,
            eventTime: future(),
            note: "Hi",
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        )
        _ = try await service.snooze(id: created.reminder.id, option: .laterToday)
        let before = try XCTUnwrap(service.reminder(id: created.reminder.id))
        let beforeIDs = Set(scheduler.scheduled.map(\.identifier))
        let beforeCount = scheduler.scheduled.count
        let beforeSnooze = before.snooze
        let beforeRules = before.rules

        let text = ReminderForwardFormatter.makeText(for: before)
        await sharing.present(text: text)

        let after = try XCTUnwrap(service.reminder(id: created.reminder.id))
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.rules, beforeRules)
        XCTAssertEqual(after.snooze, beforeSnooze)
        XCTAssertEqual(Set(scheduler.scheduled.map(\.identifier)), beforeIDs)
        XCTAssertEqual(scheduler.scheduled.count, beforeCount)
        XCTAssertEqual(sharing.presentedTexts, [text])
    }

    /// TC-FORWARD-021 Screenshot-created reminder can be forwarded
    func testScreenshotCreatedReminderCanBeForwarded() async throws {
        let person = try people.create(name: "Child 1")
        let context = try contexts.create(name: "Doctor", personID: person.id)
        let draft = ReminderDraft(
            title: "Dentist",
            titleWasFallback: false,
            dateState: .resolved(DateComponents(year: 2026, month: 9, day: 18)),
            timeState: .resolved(DateComponents(hour: 16, minute: 0)),
            note: "Bring reports",
            personName: nil,
            contextName: nil,
            personID: person.id,
            contextID: context.id,
            proposedRecurrence: nil,
            timeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: "en_GB",
            sourceText: "Dentist"
        )
        let result = try await service.createFromConfirmedDraft(draft)
        let resolver = ReminderMetadataResolver(personService: people, contextService: contexts)
        let text = ReminderForwardFormatter.makeText(
            for: result.reminder,
            personName: resolver.personName(for: result.reminder),
            contextName: resolver.contextName(for: result.reminder)
        )
        XCTAssertTrue(text.contains("Dentist"))
        XCTAssertTrue(text.contains("For: Child 1"))
        XCTAssertTrue(text.contains("Context: Doctor"))
        XCTAssertTrue(text.contains("Bring reports"))
        await sharing.present(text: text)
        XCTAssertEqual(sharing.presentedTexts.last, text)
    }

    /// TC-FORWARD-022 Native sharing service receives exact text
    func testSharingServiceReceivesExactText() async {
        let text = "Hello Forward"
        await sharing.present(text: text)
        XCTAssertEqual(sharing.presentedTexts, [text])
    }

    /// TC-FORWARD-023 No Share Extension exists
    func testNoShareExtensionExists() {
        let shareExtensionBundles = Bundle.allBundles.filter {
            ($0.bundleIdentifier ?? "").contains("shareextension")
                || ($0.bundlePath as NSString).lastPathComponent.lowercased().contains("share")
        }.filter {
            ($0.infoDictionary?["NSExtension"] as? [String: Any]) != nil
        }
        XCTAssertTrue(shareExtensionBundles.isEmpty)
        XCTAssertNil(Bundle.main.infoDictionary?["NSExtension"])
    }

    /// Sprint 7 follow-up: mismatched person-specific context rejected
    func testMismatchedPersonSpecificContextRejected() async throws {
        let child1 = try people.create(name: "Child 1")
        let child2 = try people.create(name: "Child 2")
        let child2Doctor = try contexts.create(name: "Doctor", personID: child2.id)
        do {
            _ = try await service.create(
                title: "Visit",
                eventDate: future(),
                includeTime: false,
                eventTime: nil,
                personID: child1.id,
                contextID: child2Doctor.id
            )
            XCTFail("Expected invalid context for mismatched person")
        } catch {
            XCTAssertEqual(error as? ReminderValidationError, .invalidContext)
        }
    }

    /// Sprint 7 follow-up: archived person can remain on edit
    func testArchivedPersonRemainsEditable() async throws {
        let person = try people.create(name: "Child 1")
        let created = try await service.create(
            title: "Keep",
            eventDate: future(),
            includeTime: false,
            eventTime: nil,
            personID: person.id
        )
        _ = try people.archive(id: person.id)
        var edited = created.reminder
        edited.note = "Still ok"
        let result = try await service.update(edited)
        XCTAssertEqual(result.reminder.personID, person.id)
        XCTAssertEqual(result.reminder.note, "Still ok")
    }
}

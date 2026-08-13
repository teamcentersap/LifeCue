import XCTest
@testable import LifeCue

@MainActor
final class PersonServiceTests: XCTestCase {
    private var people: PersonService!
    private var repo: InMemoryPersonRepository!

    override func setUp() {
        super.setUp()
        repo = InMemoryPersonRepository()
        people = PersonService(repository: repo, clock: {
            Date(timeIntervalSince1970: 1_800_000_000)
        })
    }

    /// TC-PEOPLE-001 Create person
    func testCreatePerson() throws {
        let person = try people.create(name: "Saachi", relationship: "Daughter")
        XCTAssertEqual(person.name, "Saachi")
        XCTAssertEqual(person.relationship, "Daughter")
        XCTAssertFalse(person.isArchived)
        XCTAssertEqual(try people.allPeople().count, 1)
    }

    /// TC-PEOPLE-002 Reject empty person name
    func testRejectEmptyPersonName() {
        XCTAssertThrowsError(try people.create(name: "   ")) { error in
            XCTAssertEqual(error as? PersonValidationError, .emptyName)
        }
    }

    /// TC-PEOPLE-003 Edit person
    func testEditPerson() throws {
        var person = try people.create(name: "Saachi")
        person.name = "Saachi K"
        person.relationship = "Daughter"
        let updated = try people.update(person)
        XCTAssertEqual(updated.name, "Saachi K")
        XCTAssertEqual(updated.relationship, "Daughter")
    }

    /// TC-PEOPLE-004 Archive person
    func testArchivePerson() throws {
        let person = try people.create(name: "Sanchit")
        let archived = try people.archive(id: person.id)
        XCTAssertTrue(archived.isArchived)
        XCTAssertTrue(try people.allPeople().isEmpty)
        XCTAssertEqual(try people.allPeople(includeArchived: true).count, 1)
    }

    /// TC-PEOPLE-005 Multiple people allowed
    func testMultiplePeopleAllowed() throws {
        _ = try people.create(name: "Me")
        _ = try people.create(name: "Child 1")
        _ = try people.create(name: "Child 2")
        XCTAssertEqual(try people.allPeople().count, 3)
    }
}

@MainActor
final class ContextServiceTests: XCTestCase {
    private var people: PersonService!
    private var contexts: ContextService!
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!

    override func setUp() {
        super.setUp()
        personRepo = InMemoryPersonRepository()
        contextRepo = InMemoryContextRepository()
        people = PersonService(repository: personRepo)
        contexts = ContextService(repository: contextRepo, personRepository: personRepo)
    }

    /// TC-CONTEXT-001 Create global context
    func testCreateGlobalContext() throws {
        let context = try contexts.create(name: "Office")
        XCTAssertNil(context.personID)
        XCTAssertTrue(context.isGlobal)
    }

    /// TC-CONTEXT-002 Create person-specific context
    func testCreatePersonSpecificContext() throws {
        let child = try people.create(name: "Child 1")
        let context = try contexts.create(name: "Doctor", personID: child.id)
        XCTAssertEqual(context.personID, child.id)
    }

    /// TC-CONTEXT-003 Same context name allowed for different people
    func testSameContextNameForDifferentPeople() throws {
        let a = try people.create(name: "Child 1")
        let b = try people.create(name: "Child 2")
        let c1 = try contexts.create(name: "Doctor", personID: a.id)
        let c2 = try contexts.create(name: "Doctor", personID: b.id)
        XCTAssertEqual(c1.name, c2.name)
        XCTAssertNotEqual(c1.id, c2.id)
        XCTAssertNotEqual(c1.personID, c2.personID)
    }

    /// TC-CONTEXT-004 Reject empty context name
    func testRejectEmptyContextName() {
        XCTAssertThrowsError(try contexts.create(name: " ")) { error in
            XCTAssertEqual(error as? ContextValidationError, .emptyName)
        }
    }

    /// TC-CONTEXT-005 Archive context
    func testArchiveContext() throws {
        let context = try contexts.create(name: "School")
        let archived = try contexts.archive(id: context.id)
        XCTAssertTrue(archived.isArchived)
        XCTAssertTrue(try contexts.allContexts().isEmpty)
    }

    /// TC-CONTEXT-006 Context references correct Person
    func testContextReferencesCorrectPerson() throws {
        let child = try people.create(name: "Child 1")
        let context = try contexts.create(name: "Doctor", personID: child.id)
        let loaded = try XCTUnwrap(contexts.context(id: context.id))
        XCTAssertEqual(loaded.personID, child.id)
    }
}

@MainActor
final class ReminderMetadataTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var reminderRepo: InMemoryReminderRepository!
    private var scheduler: FakeNotificationScheduler!
    private var service: ReminderService!
    private var people: PersonService!
    private var contexts: ContextService!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        personRepo = InMemoryPersonRepository()
        contextRepo = InMemoryContextRepository()
        reminderRepo = InMemoryReminderRepository()
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
    }

    private func futureEvent(days: Int = 5) -> Date {
        calendar.date(byAdding: .day, value: days, to: now)!
    }

    /// TC-REMINDER-META-001 Create without person/context
    func testCreateWithoutPersonOrContext() async throws {
        let result = try await service.create(
            title: "Pay electricity bill",
            eventDate: futureEvent(),
            includeTime: false,
            eventTime: nil,
            note: nil,
            rules: [.exactAtEvent()]
        )
        XCTAssertNil(result.reminder.personID)
        XCTAssertNil(result.reminder.contextID)
    }

    /// TC-REMINDER-META-002 Create with person
    func testCreateWithPerson() async throws {
        let person = try people.create(name: "Child 1")
        let result = try await service.create(
            title: "Pickup",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            note: nil,
            rules: [.exactAtEvent()],
            personID: person.id
        )
        XCTAssertEqual(result.reminder.personID, person.id)
    }

    /// TC-REMINDER-META-003 Create with context
    func testCreateWithContext() async throws {
        let context = try contexts.create(name: "School")
        let result = try await service.create(
            title: "Form due",
            eventDate: futureEvent(),
            includeTime: false,
            eventTime: nil,
            rules: [.exactAtEvent()],
            contextID: context.id
        )
        XCTAssertEqual(result.reminder.contextID, context.id)
    }

    /// TC-REMINDER-META-004 Create with person + context
    func testCreateWithPersonAndContext() async throws {
        let person = try people.create(name: "Child 1")
        let context = try contexts.create(name: "Doctor", personID: person.id)
        let result = try await service.create(
            title: "Appointment",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            rules: [.exactAtEvent()],
            personID: person.id,
            contextID: context.id
        )
        XCTAssertEqual(result.reminder.personID, person.id)
        XCTAssertEqual(result.reminder.contextID, context.id)
    }

    /// TC-REMINDER-META-005 Edit person without changing schedule
    func testEditPersonWithoutChangingSchedule() async throws {
        let personA = try people.create(name: "Child 1")
        let personB = try people.create(name: "Child 2")
        let created = try await service.create(
            title: "Doctor",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)],
            personID: personA.id
        )
        let beforeIDs = Set(scheduler.scheduled.map(\.identifier))
        let beforeFires = Set(scheduler.scheduled.map(\.fireAt))
        var edited = created.reminder
        edited.personID = personB.id
        let result = try await service.update(edited)
        XCTAssertEqual(result.reminder.personID, personB.id)
        XCTAssertEqual(result.scheduleOutcome, ReminderScheduleOutcome.nothingToSchedule)
        XCTAssertEqual(Set(scheduler.scheduled.map(\.identifier)), beforeIDs)
        XCTAssertEqual(Set(scheduler.scheduled.map(\.fireAt)), beforeFires)
    }

    /// TC-REMINDER-META-006 Edit context without changing schedule
    func testEditContextWithoutChangingSchedule() async throws {
        let school = try contexts.create(name: "School")
        let doctor = try contexts.create(name: "Doctor")
        let created = try await service.create(
            title: "Visit",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            rules: [.exactAtEvent()],
            contextID: school.id
        )
        let beforeIDs = Set(scheduler.scheduled.map(\.identifier))
        var edited = created.reminder
        edited.contextID = doctor.id
        _ = try await service.update(edited)
        XCTAssertEqual(Set(scheduler.scheduled.map(\.identifier)), beforeIDs)
    }

    /// TC-REMINDER-META-007 Invalid person rejected
    func testInvalidPersonRejected() async throws {
        do {
            _ = try await service.create(
                title: "X",
                eventDate: futureEvent(),
                includeTime: false,
                eventTime: nil,
                note: nil,
                personID: UUID()
            )
            XCTFail("Expected invalid person")
        } catch {
            XCTAssertEqual(error as? ReminderValidationError, .invalidPerson)
        }
    }

    /// TC-REMINDER-META-008 Invalid context rejected
    func testInvalidContextRejected() async throws {
        do {
            _ = try await service.create(
                title: "X",
                eventDate: futureEvent(),
                includeTime: false,
                eventTime: nil,
                note: nil,
                contextID: UUID()
            )
            XCTFail("Expected invalid context")
        } catch {
            XCTAssertEqual(error as? ReminderValidationError, .invalidContext)
        }
    }

    /// TC-REMINDER-META-009 Archive person does not delete reminders
    func testArchivePersonDoesNotDeleteReminders() async throws {
        let person = try people.create(name: "Child 1")
        let created = try await service.create(
            title: "Keep me",
            eventDate: futureEvent(),
            includeTime: false,
            eventTime: nil,
            personID: person.id
        )
        _ = try people.archive(id: person.id)
        let stored = try XCTUnwrap(service.reminder(id: created.reminder.id))
        XCTAssertEqual(stored.personID, person.id)
        XCTAssertEqual(try service.allReminders().count, 1)
    }

    /// TC-REMINDER-META-010 Archive context does not delete reminders
    func testArchiveContextDoesNotDeleteReminders() async throws {
        let context = try contexts.create(name: "Office")
        let created = try await service.create(
            title: "Keep me",
            eventDate: futureEvent(),
            includeTime: false,
            eventTime: nil,
            contextID: context.id
        )
        _ = try contexts.archive(id: context.id)
        let stored = try XCTUnwrap(service.reminder(id: created.reminder.id))
        XCTAssertEqual(stored.contextID, context.id)
    }

    /// TC-REMINDER-META-011 Legacy reminder loads with nil metadata
    func testLegacyReminderNilMetadata() throws {
        let reminder = Reminder(
            title: "Legacy",
            eventDate: DateComponents(year: 2026, month: 9, day: 1),
            eventTime: nil
        )
        XCTAssertNil(reminder.personID)
        XCTAssertNil(reminder.contextID)
        try reminderRepo.save(reminder)
        let loaded = try XCTUnwrap(reminderRepo.fetch(id: reminder.id))
        XCTAssertNil(loaded.personID)
        XCTAssertNil(loaded.contextID)
    }

    /// TC-REMINDER-META-012 Screenshot-created reminder supports person/context
    func testScreenshotCreateSupportsPersonContext() async throws {
        let person = try people.create(name: "Child 1")
        let context = try contexts.create(name: "Doctor", personID: person.id)
        var draft = ReminderDraft(
            title: "Dentist",
            titleWasFallback: false,
            dateState: .resolved(DateComponents(year: 2026, month: 9, day: 18)),
            timeState: .resolved(DateComponents(hour: 16, minute: 0)),
            note: "Bring reports",
            personName: "hint",
            contextName: "hint",
            personID: person.id,
            contextID: context.id,
            proposedRecurrence: nil,
            timeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: "en_GB",
            sourceText: "Dentist"
        )
        let result = try await service.createFromConfirmedDraft(draft)
        XCTAssertEqual(result.reminder.personID, person.id)
        XCTAssertEqual(result.reminder.contextID, context.id)
        XCTAssertEqual(result.reminder.note, "Bring reports")
    }

    /// TC-REMINDER-META-013 No duplicate notifications on metadata edit
    func testMetadataEditDoesNotDuplicateNotifications() async throws {
        let person = try people.create(name: "Me")
        let created = try await service.create(
            title: "Bill",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        )
        let count = scheduler.scheduled.count
        var edited = created.reminder
        edited.personID = person.id
        _ = try await service.update(edited)
        XCTAssertEqual(scheduler.scheduled.count, count)
    }

    /// TC-REMINDER-META-014 Preserve recurrence on metadata edit
    func testMetadataEditPreservesRecurrence() async throws {
        let created = try await service.create(
            title: "Daily meds",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            rules: [.recurring(.daily())]
        )
        let person = try people.create(name: "Me")
        var edited = created.reminder
        edited.personID = person.id
        let updated = try await service.update(edited)
        XCTAssertEqual(updated.reminder.rules.first?.ruleType, .recurring)
        XCTAssertEqual(updated.reminder.rules.first?.recurrence?.frequency, .daily)
    }

    /// TC-REMINDER-META-015 Preserve snooze on metadata edit
    func testMetadataEditPreservesSnooze() async throws {
        let created = try await service.create(
            title: "Call",
            eventDate: futureEvent(),
            includeTime: true,
            eventTime: futureEvent(),
            rules: [.exactAtEvent()]
        )
        _ = try await service.snooze(id: created.reminder.id, option: .laterToday)
        let snoozed = try XCTUnwrap(service.reminder(id: created.reminder.id))
        XCTAssertNotNil(snoozed.snooze)
        let person = try people.create(name: "Me")
        var edited = snoozed
        edited.personID = person.id
        let updated = try await service.update(edited)
        XCTAssertNotNil(updated.reminder.snooze)
        XCTAssertEqual(updated.reminder.snooze?.until, snoozed.snooze?.until)
    }
}

@MainActor
final class ReminderPeoplePersistenceTests: XCTestCase {
    func testSwiftDataRoundTripPersonContextIDs() throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let context = container.mainContext
        let reminders = SwiftDataReminderRepository(modelContext: context)
        let people = SwiftDataPersonRepository(modelContext: context)
        let contexts = SwiftDataContextRepository(modelContext: context)

        let person = Person(name: "Saachi", relationship: "Daughter")
        try people.save(person)
        let ctx = ReminderContext(name: "Doctor", personID: person.id)
        try contexts.save(ctx)

        let reminder = Reminder(
            title: "Checkup",
            eventDate: DateComponents(year: 2026, month: 9, day: 18),
            eventTime: DateComponents(hour: 16, minute: 0),
            personID: person.id,
            contextID: ctx.id
        )
        try reminders.save(reminder)
        let loaded = try XCTUnwrap(reminders.fetch(id: reminder.id))
        XCTAssertEqual(loaded.personID, person.id)
        XCTAssertEqual(loaded.contextID, ctx.id)
        XCTAssertEqual(try people.fetch(id: person.id)?.name, "Saachi")
        XCTAssertEqual(try contexts.fetch(id: ctx.id)?.personID, person.id)
    }
}

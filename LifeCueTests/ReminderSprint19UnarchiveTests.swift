import XCTest
@testable import LifeCue

@MainActor
final class ReminderSprint19UnarchiveTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var reminderRepo: InMemoryReminderRepository!
    private var scheduler: FakeNotificationScheduler!
    private var reminderService: ReminderService!
    private var personService: PersonService!
    private var contextService: ContextService!
    private var deletion: OrganizationDeletionService!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 10))!
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
        personService = PersonService(repository: personRepo, clock: { self.now })
        contextService = ContextService(
            repository: contextRepo,
            personRepository: personRepo,
            clock: { self.now }
        )
        deletion = OrganizationDeletionService(
            personRepository: personRepo,
            contextRepository: contextRepo,
            reminderService: reminderService,
            personCascade: InMemoryPersonCascadeDeleter(
                personRepository: personRepo,
                contextRepository: contextRepo
            )
        )
    }

    private func eventDate(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: 9))!
    }

    // MARK: - UI contract

    func testOrganizationListScopeHasActiveAndArchivedOnly() {
        XCTAssertEqual(OrganizationListScope.default, .active)
        XCTAssertEqual(OrganizationListScope.segmentTitles, ["Active", "Archived"])
        XCTAssertFalse(OrganizationListScope.segmentTitles.contains("All"))
        XCTAssertEqual(OrganizationListScope.allCases.count, 2)
    }

    func testActiveSegmentShowsOnlyActivePeople() throws {
        let active = try personService.create(name: "Active")
        let archived = try personService.create(name: "Archived")
        _ = try personService.archive(id: archived.id)
        let all = try personService.allPeople(includeArchived: true)
        let shown = OrganizationListPresentation.people(from: all, scope: .active)
        XCTAssertEqual(shown.map(\.id), [active.id])
    }

    func testArchivedSegmentShowsOnlyArchivedPeople() throws {
        let active = try personService.create(name: "Active")
        let archived = try personService.create(name: "Archived")
        _ = try personService.archive(id: archived.id)
        let all = try personService.allPeople(includeArchived: true)
        let shown = OrganizationListPresentation.people(from: all, scope: .archived)
        XCTAssertEqual(shown.map(\.id), [archived.id])
        XCTAssertFalse(shown.contains(where: { $0.id == active.id }))
    }

    func testActiveSegmentShowsOnlyActiveContexts() throws {
        let active = try contextService.create(name: "Active")
        let archived = try contextService.create(name: "Archived")
        _ = try contextService.archive(id: archived.id)
        let all = try contextService.allContexts(includeArchived: true)
        let shown = OrganizationListPresentation.contexts(from: all, scope: .active)
        XCTAssertEqual(shown.map(\.id), [active.id])
    }

    func testArchivedSegmentShowsOnlyArchivedContexts() throws {
        let active = try contextService.create(name: "Active")
        let archived = try contextService.create(name: "Archived")
        _ = try contextService.archive(id: archived.id)
        let all = try contextService.allContexts(includeArchived: true)
        let shown = OrganizationListPresentation.contexts(from: all, scope: .archived)
        XCTAssertEqual(shown.map(\.id), [archived.id])
        XCTAssertFalse(shown.contains(where: { $0.id == active.id }))
    }

    func testEmptyArchivedMessages() {
        XCTAssertEqual(
            OrganizationListPresentation.emptyPeopleMessage(for: .archived),
            "No archived people."
        )
        XCTAssertEqual(
            OrganizationListPresentation.emptyContextsMessage(for: .archived),
            "No archived contexts."
        )
    }

    func testContextDetailUnarchiveActionContract() {
        XCTAssertEqual(ContextDetailView.preferredRowTapAction, .openDetail)
        XCTAssertEqual(ContextDetailView.preferredExplicitArchiveAction, .archive)
        XCTAssertEqual(ContextDetailView.preferredExplicitUnarchiveAction, .unarchive)
    }

    // MARK: - Person unarchive

    func testUnarchivePersonSetsIsArchivedFalseAndKeepsID() throws {
        let person = try personService.create(name: "John", relationship: "Dad")
        let originalID = person.id
        _ = try personService.archive(id: person.id)
        let restored = try personService.unarchive(id: person.id)
        XCTAssertFalse(restored.isArchived)
        XCTAssertEqual(restored.id, originalID)
        XCTAssertEqual(restored.name, "John")
        XCTAssertEqual(restored.relationship, "Dad")
        XCTAssertTrue(try personService.allPeople().contains(where: { $0.id == originalID }))
        XCTAssertFalse(
            OrganizationListPresentation.people(
                from: try personService.allPeople(includeArchived: true),
                scope: .archived
            ).contains(where: { $0.id == originalID })
        )
    }

    func testUnarchivePersonDoesNotCascadeToContextsOrReminders() async throws {
        let person = try personService.create(name: "John")
        let doctor = try contextService.create(name: "Doctor", personID: person.id)
        let school = try contextService.create(name: "School", personID: person.id)
        let reminder = try await reminderService.create(
            title: "Checkup",
            eventDate: eventDate(20),
            includeTime: true,
            eventTime: eventDate(20),
            personID: person.id,
            contextID: doctor.id
        )
        let scheduledBefore = scheduler.scheduled.map(\.identifier)

        _ = try contextService.archive(id: doctor.id)
        _ = try contextService.archive(id: school.id)
        _ = try personService.archive(id: person.id)
        _ = try personService.unarchive(id: person.id)

        XCTAssertFalse(try personService.person(id: person.id)?.isArchived == true)
        XCTAssertTrue(try contextService.context(id: doctor.id)?.isArchived == true)
        XCTAssertTrue(try contextService.context(id: school.id)?.isArchived == true)
        let kept = try XCTUnwrap(try reminderService.reminder(id: reminder.reminder.id))
        XCTAssertEqual(kept.personID, person.id)
        XCTAssertEqual(kept.contextID, doctor.id)
        XCTAssertEqual(kept.id, reminder.reminder.id)
        XCTAssertEqual(scheduler.scheduled.map(\.identifier), scheduledBefore)
    }

    func testArchivedPersonCanStillBePermanentlyDeleted() async throws {
        let person = try personService.create(name: "Gone")
        let context = try contextService.create(name: "Health", personID: person.id)
        _ = try await reminderService.create(
            title: "R",
            eventDate: eventDate(20),
            includeTime: true,
            eventTime: eventDate(20),
            personID: person.id,
            contextID: context.id
        )
        _ = try personService.archive(id: person.id)
        try await deletion.permanentlyDeletePerson(id: person.id)
        XCTAssertNil(try personService.person(id: person.id))
        XCTAssertNil(try contextService.context(id: context.id))
    }

    func testPersonUnarchivePersistenceFailureLeavesArchived() throws {
        let inner = InMemoryPersonRepository()
        let failing = FailingSavePersonRepository(inner: inner)
        let service = PersonService(repository: failing, clock: { self.now })
        let person = try service.create(name: "Fail")
        _ = try service.archive(id: person.id)
        failing.failNextSave = true
        XCTAssertThrowsError(try service.unarchive(id: person.id))
        XCTAssertTrue(try service.person(id: person.id)?.isArchived == true)
        let active = OrganizationListPresentation.people(
            from: try service.allPeople(includeArchived: true),
            scope: .active
        )
        XCTAssertFalse(active.contains(where: { $0.id == person.id }))
    }

    // MARK: - Context unarchive

    func testUnarchiveContextSetsIsArchivedFalseAndKeepsIDs() throws {
        let person = try personService.create(name: "Owner")
        let context = try contextService.create(name: "Health", personID: person.id)
        let contextID = context.id
        let personID = context.personID
        _ = try contextService.archive(id: context.id)
        let restored = try contextService.unarchive(id: context.id)
        XCTAssertFalse(restored.isArchived)
        XCTAssertEqual(restored.id, contextID)
        XCTAssertEqual(restored.personID, personID)
        XCTAssertEqual(restored.name, "Health")
    }

    func testUnarchiveContextDoesNotUnarchivePersonOrChangeReminders() async throws {
        let person = try personService.create(name: "Owner")
        let context = try contextService.create(name: "Health", personID: person.id)
        let reminder = try await reminderService.create(
            title: "Meds",
            eventDate: eventDate(21),
            includeTime: true,
            eventTime: eventDate(21),
            personID: person.id,
            contextID: context.id
        )
        let scheduledBefore = scheduler.scheduled.map(\.identifier)

        _ = try personService.archive(id: person.id)
        _ = try contextService.archive(id: context.id)
        _ = try contextService.unarchive(id: context.id)

        XCTAssertFalse(try contextService.context(id: context.id)?.isArchived == true)
        XCTAssertTrue(try personService.person(id: person.id)?.isArchived == true)
        let kept = try XCTUnwrap(try reminderService.reminder(id: reminder.reminder.id))
        XCTAssertEqual(kept.contextID, context.id)
        XCTAssertEqual(kept.personID, person.id)
        XCTAssertEqual(scheduler.scheduled.map(\.identifier), scheduledBefore)
    }

    func testArchivedContextCanStillBePermanentlyDeleted() async throws {
        let context = try contextService.create(name: "Temp")
        _ = try await reminderService.create(
            title: "R",
            eventDate: eventDate(22),
            includeTime: true,
            eventTime: eventDate(22),
            contextID: context.id
        )
        _ = try contextService.archive(id: context.id)
        try await deletion.permanentlyDeleteContext(id: context.id)
        XCTAssertNil(try contextService.context(id: context.id))
    }

    func testContextUnarchivePersistenceFailureLeavesArchived() throws {
        let personInner = InMemoryPersonRepository()
        let contextInner = InMemoryContextRepository()
        let failing = FailingSaveContextRepository(inner: contextInner)
        let people = PersonService(repository: personInner, clock: { self.now })
        let contexts = ContextService(
            repository: failing,
            personRepository: personInner,
            clock: { self.now }
        )
        let person = try people.create(name: "Owner")
        let context = try contexts.create(name: "Health", personID: person.id)
        _ = try contexts.archive(id: context.id)
        failing.failNextSave = true
        XCTAssertThrowsError(try contexts.unarchive(id: context.id))
        XCTAssertTrue(try contexts.context(id: context.id)?.isArchived == true)
        let active = OrganizationListPresentation.contexts(
            from: try contexts.allContexts(includeArchived: true),
            scope: .active
        )
        XCTAssertFalse(active.contains(where: { $0.id == context.id }))
    }

    // MARK: - Backup

    func testBackupExportValidAfterArchiveUnarchive() throws {
        let person = try personService.create(name: "Backup")
        let context = try contextService.create(name: "Health", personID: person.id)
        _ = try personService.archive(id: person.id)
        _ = try contextService.archive(id: context.id)
        _ = try personService.unarchive(id: person.id)
        _ = try contextService.unarchive(id: context.id)

        let export = BackupExportService(
            reminderRepository: reminderRepo,
            personRepository: personRepo,
            contextRepository: contextRepo
        )
        let result = try export.exportBackup(exportedAt: now)
        XCTAssertNoThrow(try BackupValidator.validateExport(result.backup))
        XCTAssertEqual(result.backup.people.first(where: { $0.id == person.id })?.isArchived, false)
        XCTAssertEqual(result.backup.contexts.first(where: { $0.id == context.id })?.isArchived, false)
    }
}

// MARK: - Test doubles

@MainActor
private final class FailingSavePersonRepository: PersonRepository {
    private let inner: InMemoryPersonRepository
    var failNextSave = false

    init(inner: InMemoryPersonRepository) {
        self.inner = inner
    }

    func fetchAll() throws -> [Person] { try inner.fetchAll() }
    func fetch(id: UUID) throws -> Person? { try inner.fetch(id: id) }
    func delete(id: UUID) throws { try inner.delete(id: id) }

    func save(_ person: Person) throws {
        if failNextSave {
            failNextSave = false
            throw PersonValidationError.notFound
        }
        try inner.save(person)
    }
}

@MainActor
private final class FailingSaveContextRepository: ContextRepository {
    private let inner: InMemoryContextRepository
    var failNextSave = false

    init(inner: InMemoryContextRepository) {
        self.inner = inner
    }

    func fetchAll() throws -> [ReminderContext] { try inner.fetchAll() }
    func fetch(id: UUID) throws -> ReminderContext? { try inner.fetch(id: id) }
    func delete(id: UUID) throws { try inner.delete(id: id) }

    func save(_ context: ReminderContext) throws {
        if failNextSave {
            failNextSave = false
            throw ContextValidationError.notFound
        }
        try inner.save(context)
    }
}

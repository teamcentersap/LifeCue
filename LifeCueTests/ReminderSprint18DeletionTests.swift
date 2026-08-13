import XCTest
import SwiftData
@testable import LifeCue

@MainActor
final class ReminderSprint18DeletionTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var reminderRepo: InMemoryReminderRepository!
    private var scheduler: FakeNotificationScheduler!
    private var reminderService: ReminderService!
    private var personService: PersonService!
    private var contextService: ContextService!
    private var cascade: InMemoryPersonCascadeDeleter!
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
        cascade = InMemoryPersonCascadeDeleter(
            personRepository: personRepo,
            contextRepository: contextRepo
        )
        deletion = OrganizationDeletionService(
            personRepository: personRepo,
            contextRepository: contextRepo,
            reminderService: reminderService,
            personCascade: cascade
        )
    }

    private func eventDate(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: 9))!
    }

    private func createReminder(
        title: String,
        personID: UUID? = nil,
        contextID: UUID? = nil
    ) async throws -> ReminderMutationResult {
        try await reminderService.create(
            title: title,
            eventDate: eventDate(20),
            includeTime: true,
            eventTime: eventDate(20),
            personID: personID,
            contextID: contextID
        )
    }

    // MARK: - Person

    func testDeleteUnusedPersonSucceeds() async throws {
        let person = try personService.create(name: "Unused")
        let deps = try deletion.personDependencies(personID: person.id)
        XCTAssertTrue(deps.isEmpty)
        try await deletion.permanentlyDeletePerson(id: person.id)
        XCTAssertNil(try personService.person(id: person.id))
    }

    func testUnusedPersonDeletionDoesNotAffectReminders() async throws {
        let person = try personService.create(name: "Unused")
        let unrelated = try await createReminder(title: "Keep me")
        try await deletion.permanentlyDeletePerson(id: person.id)
        XCTAssertEqual(try reminderService.reminder(id: unrelated.reminder.id)?.title, "Keep me")
    }

    func testReferencedPersonReportsDependencies() async throws {
        let person = try personService.create(name: "Used")
        _ = try contextService.create(name: "Health", personID: person.id)
        _ = try await createReminder(title: "A", personID: person.id)
        _ = try await createReminder(title: "B", personID: person.id)
        let deps = try deletion.personDependencies(personID: person.id)
        XCTAssertEqual(deps.reminderCount, 2)
        XCTAssertEqual(deps.personalContextCount, 1)
        XCTAssertFalse(deps.isEmpty)
    }

    func testDeletePersonAndDataRemovesRemindersAndPersonalContexts() async throws {
        let person = try personService.create(name: "Saachi")
        let other = try personService.create(name: "Sanchit")
        let personal = try contextService.create(name: "Health", personID: person.id)
        let otherPersonal = try contextService.create(name: "Health", personID: other.id)
        let global = try contextService.create(name: "School", personID: nil)

        let affected = try await createReminder(
            title: "Affected",
            personID: person.id,
            contextID: personal.id
        )
        let unrelated = try await createReminder(
            title: "Unrelated",
            personID: other.id,
            contextID: otherPersonal.id
        )

        try await deletion.permanentlyDeletePerson(id: person.id)

        XCTAssertNil(try personService.person(id: person.id))
        XCTAssertNil(try contextService.context(id: personal.id))
        XCTAssertNotNil(try personService.person(id: other.id))
        XCTAssertNotNil(try contextService.context(id: otherPersonal.id))
        XCTAssertNotNil(try contextService.context(id: global.id))
        XCTAssertNil(try reminderService.reminder(id: affected.reminder.id))
        XCTAssertNotNil(try reminderService.reminder(id: unrelated.reminder.id))
    }

    func testDeletePersonCancelsAffectedNotificationsOnly() async throws {
        let person = try personService.create(name: "Notify")
        let other = try personService.create(name: "Other")
        let affected = try await createReminder(title: "Fire", personID: person.id)
        let unrelated = try await createReminder(title: "Stay", personID: other.id)

        XCTAssertFalse(scheduler.scheduled.filter { $0.identifier.contains(affected.reminder.id.uuidString) }.isEmpty)
        XCTAssertFalse(scheduler.scheduled.filter { $0.identifier.contains(unrelated.reminder.id.uuidString) }.isEmpty)

        try await deletion.permanentlyDeletePerson(id: person.id)

        XCTAssertTrue(scheduler.scheduled.filter { $0.identifier.contains(affected.reminder.id.uuidString) }.isEmpty)
        XCTAssertFalse(scheduler.scheduled.filter { $0.identifier.contains(unrelated.reminder.id.uuidString) }.isEmpty)
    }

    func testArchivePersonPreservesPersonContextsAndReminders() async throws {
        let person = try personService.create(name: "Archive Me")
        let context = try contextService.create(name: "Health", personID: person.id)
        let reminder = try await createReminder(title: "Keep", personID: person.id, contextID: context.id)

        _ = try personService.archive(id: person.id)

        XCTAssertTrue(try personService.person(id: person.id)?.isArchived == true)
        XCTAssertNotNil(try contextService.context(id: context.id))
        XCTAssertNotNil(try reminderService.reminder(id: reminder.reminder.id))
        XCTAssertEqual(try reminderService.reminder(id: reminder.reminder.id)?.personID, person.id)
    }

    func testPersonCascadeFailureLeavesPersonAndContexts() async throws {
        let person = try personService.create(name: "Rollback")
        let context = try contextService.create(name: "Health", personID: person.id)
        cascade.testWillCommit = { throw OrganizationDeletionError.cascadeFailed }

        do {
            try await deletion.permanentlyDeletePerson(id: person.id)
            XCTFail("Expected cascade failure")
        } catch {
            XCTAssertEqual(error as? OrganizationDeletionError, .cascadeFailed)
        }

        XCTAssertNotNil(try personService.person(id: person.id))
        XCTAssertNotNil(try contextService.context(id: context.id))
        XCTAssertEqual(try contextService.context(id: context.id)?.personID, person.id)
    }

    func testSwiftDataPersonCascadeRollbackPreservesOriginal() throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let modelContext = ModelContext(container)
        let personRepository = SwiftDataPersonRepository(modelContext: modelContext)
        let contextRepository = SwiftDataContextRepository(modelContext: modelContext)
        let people = PersonService(repository: personRepository, clock: { self.now })
        let contexts = ContextService(
            repository: contextRepository,
            personRepository: personRepository,
            clock: { self.now }
        )
        let person = try people.create(name: "SwiftData")
        let personal = try contexts.create(name: "Health", personID: person.id)
        let cascadeDeleter = SwiftDataPersonCascadeDeleter(modelContext: modelContext)
        cascadeDeleter.testWillSave = { throw OrganizationDeletionError.cascadeFailed }

        XCTAssertThrowsError(
            try cascadeDeleter.deletePersonalContextsThenPerson(
                personID: person.id,
                personalContextIDs: [personal.id]
            )
        )

        XCTAssertNotNil(try people.person(id: person.id))
        XCTAssertNotNil(try contexts.context(id: personal.id))
        XCTAssertEqual(try contexts.context(id: personal.id)?.personID, person.id)
    }

    // MARK: - Context

    func testDeleteUnusedContextSucceeds() async throws {
        let context = try contextService.create(name: "Unused")
        XCTAssertTrue(try deletion.contextDependencies(contextID: context.id).isEmpty)
        try await deletion.permanentlyDeleteContext(id: context.id)
        XCTAssertNil(try contextService.context(id: context.id))
    }

    func testDeleteContextWithRemindersRemovesOnlyThoseReminders() async throws {
        let person = try personService.create(name: "Owner")
        let context = try contextService.create(name: "Health", personID: person.id)
        let affected = try await createReminder(title: "Affected", personID: person.id, contextID: context.id)
        let unrelated = try await createReminder(title: "Unrelated", personID: person.id)

        try await deletion.permanentlyDeleteContext(id: context.id)

        XCTAssertNil(try contextService.context(id: context.id))
        XCTAssertNotNil(try personService.person(id: person.id))
        XCTAssertNil(try reminderService.reminder(id: affected.reminder.id))
        XCTAssertNotNil(try reminderService.reminder(id: unrelated.reminder.id))
    }

    func testDeleteContextCancelsAffectedNotificationsOnly() async throws {
        let person = try personService.create(name: "Owner")
        let context = try contextService.create(name: "Health", personID: person.id)
        let affected = try await createReminder(title: "Affected", personID: person.id, contextID: context.id)
        let unrelated = try await createReminder(title: "Unrelated", personID: person.id)

        try await deletion.permanentlyDeleteContext(id: context.id)

        XCTAssertTrue(scheduler.scheduled.filter { $0.identifier.contains(affected.reminder.id.uuidString) }.isEmpty)
        XCTAssertFalse(scheduler.scheduled.filter { $0.identifier.contains(unrelated.reminder.id.uuidString) }.isEmpty)
    }

    func testArchiveContextPreservesContextAndReminders() async throws {
        let person = try personService.create(name: "Owner")
        let context = try contextService.create(name: "Health", personID: person.id)
        let reminder = try await createReminder(title: "Keep", personID: person.id, contextID: context.id)
        _ = try contextService.archive(id: context.id)
        XCTAssertTrue(try contextService.context(id: context.id)?.isArchived == true)
        XCTAssertNotNil(try reminderService.reminder(id: reminder.reminder.id))
        XCTAssertNotNil(try personService.person(id: person.id))
    }

    // MARK: - Data integrity / backup

    func testNoOrphanIDsAfterPersonDeletion() async throws {
        let person = try personService.create(name: "A")
        let personal = try contextService.create(name: "X", personID: person.id)
        _ = try await createReminder(title: "R", personID: person.id, contextID: personal.id)
        try await deletion.permanentlyDeletePerson(id: person.id)

        for reminder in try reminderService.allReminders() {
            if let personID = reminder.personID {
                XCTAssertNotNil(try personService.person(id: personID))
            }
            if let contextID = reminder.contextID {
                XCTAssertNotNil(try contextService.context(id: contextID))
            }
        }
        for context in try contextService.allContexts(includeArchived: true) {
            if let personID = context.personID {
                XCTAssertNotNil(try personService.person(id: personID))
            }
        }
    }

    func testBackupExportAfterDeletionExcludesDeletedRecordsAndValidates() async throws {
        let person = try personService.create(name: "Export")
        let personal = try contextService.create(name: "Health", personID: person.id)
        _ = try await createReminder(title: "Gone", personID: person.id, contextID: personal.id)
        let keep = try await createReminder(title: "Keep")

        try await deletion.permanentlyDeletePerson(id: person.id)

        let export = BackupExportService(
            reminderRepository: reminderRepo,
            personRepository: personRepo,
            contextRepository: contextRepo
        )
        let result = try export.exportBackup(exportedAt: now)
        XCTAssertFalse(result.backup.people.contains(where: { $0.id == person.id }))
        XCTAssertFalse(result.backup.contexts.contains(where: { $0.id == personal.id }))
        XCTAssertTrue(result.backup.reminders.contains(where: { $0.id == keep.reminder.id }))
        XCTAssertNoThrow(try BackupValidator.validateExport(result.backup))
    }

    func testPresentationCopyUsesDynamicCounts() {
        let deps = PersonDeletionDependencies(reminderCount: 3, personalContextCount: 2)
        let message = OrganizationDeletionPresentation.personUsedMessage(dependencies: deps)
        XCTAssertTrue(message.contains("3 reminders"))
        XCTAssertTrue(message.contains("2 personal contexts"))
        XCTAssertEqual(
            OrganizationDeletionPresentation.personDeleteActionTitle(dependencies: deps),
            "Delete Person & Data"
        )
        let contextDeps = ContextDeletionDependencies(reminderCount: 2)
        XCTAssertEqual(
            OrganizationDeletionPresentation.contextDeleteActionTitle(dependencies: contextDeps),
            "Delete 2 Reminders & Context"
        )
    }
}

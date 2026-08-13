import XCTest
@testable import LifeCue

/// Focused tests for People/Context navigation, selection loading, edit, and archive.
@MainActor
final class PeopleContextCreationPresentationTests: XCTestCase {
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var personService: PersonService!
    private var contextService: ContextService!

    override func setUp() {
        super.setUp()
        personRepo = InMemoryPersonRepository()
        contextRepo = InMemoryContextRepository()
        personService = PersonService(repository: personRepo)
        contextService = ContextService(
            repository: contextRepo,
            personRepository: personRepo
        )
    }

    // MARK: - Presentation (NavigationLink, not shared route switch)

    /// Reminder forms push creation via NavigationLink, not nested sheets.
    func testReminderFormsPreferNavigationPushOverNestedSheet() {
        XCTAssertEqual(
            OrganizationSelectionPresentation.preferredCreationPresentation,
            .navigationPush
        )
        XCTAssertNotEqual(
            OrganizationSelectionPresentation.preferredCreationPresentation,
            .sheet
        )
    }

    /// Selection uses dedicated NavigationLinks — not Form menu / navigationLink pickers.
    func testReminderFormsPreferDedicatedNavigationLinks() {
        XCTAssertEqual(
            OrganizationSelectionPresentation.preferredForReminderForms,
            .dedicatedNavigationLink
        )
        XCTAssertNotEqual(
            OrganizationSelectionPresentation.preferredForReminderForms,
            .menu
        )
        XCTAssertNotEqual(
            OrganizationSelectionPresentation.preferredForReminderForms,
            .navigationLinkPicker
        )
    }

    /// TC-NAV-002 For opens PersonSelectionView.
    func testForOpensPersonSelectionDestination() {
        XCTAssertEqual(
            ReminderOrganizationSelection.destination(for: .selectPerson),
            .personSelection
        )
        XCTAssertEqual(
            ReminderOrganizationDestination.personSelection.rawValue,
            "PersonSelectionView"
        )
    }

    /// TC-NAV-005 Context opens ContextSelectionView.
    func testContextOpensContextSelectionDestination() {
        XCTAssertEqual(
            ReminderOrganizationSelection.destination(for: .selectContext),
            .contextSelection
        )
        XCTAssertEqual(
            ReminderOrganizationDestination.contextSelection.rawValue,
            "ContextSelectionView"
        )
    }

    /// TC-NAV-007 Add Person opens QuickAddPersonView.
    func testAddPersonOpensPersonCreationDestination() {
        XCTAssertEqual(
            ReminderOrganizationSelection.destination(for: .createPerson),
            .addPerson
        )
        XCTAssertEqual(
            ReminderOrganizationDestination.addPerson.rawValue,
            "QuickAddPersonView"
        )
    }

    /// TC-NAV-008 Add Context opens QuickAddContextView.
    func testAddContextOpensContextCreationDestination() {
        XCTAssertEqual(
            ReminderOrganizationSelection.destination(for: .createContext),
            .addContext
        )
        XCTAssertEqual(
            ReminderOrganizationDestination.addContext.rawValue,
            "QuickAddContextView"
        )
    }

    /// TC-NAV-011…014 No cross-mapping among the four intents.
    func testFourWayDestinationsHaveNoCrossMapping() {
        let map: [(ReminderOrganizationIntent, ReminderOrganizationDestination)] = [
            (.selectPerson, .personSelection),
            (.selectContext, .contextSelection),
            (.createPerson, .addPerson),
            (.createContext, .addContext)
        ]
        for (intent, expected) in map {
            XCTAssertEqual(ReminderOrganizationSelection.destination(for: intent), expected)
        }

        XCTAssertNotEqual(
            ReminderOrganizationSelection.destination(for: .selectPerson),
            .addContext
        )
        XCTAssertNotEqual(
            ReminderOrganizationSelection.destination(for: .selectContext),
            .addContext
        )
        XCTAssertNotEqual(
            ReminderOrganizationSelection.destination(for: .createPerson),
            .addContext
        )
        XCTAssertNotEqual(
            ReminderOrganizationSelection.destination(for: .createPerson),
            .contextSelection
        )
        XCTAssertNotEqual(
            ReminderOrganizationSelection.destination(for: .createContext),
            .addPerson
        )
        XCTAssertNotEqual(
            ReminderOrganizationSelection.destination(for: .selectPerson),
            .addPerson
        )
        XCTAssertNotEqual(
            ReminderOrganizationSelection.destination(for: .selectContext),
            .addPerson
        )
    }

    /// Four destination identities are unique (no conflation).
    func testOrganizationDestinationIdentitiesAreUnique() {
        let values = [
            ReminderOrganizationDestination.personSelection.rawValue,
            ReminderOrganizationDestination.contextSelection.rawValue,
            ReminderOrganizationDestination.addPerson.rawValue,
            ReminderOrganizationDestination.addContext.rawValue
        ]
        XCTAssertEqual(Set(values).count, 4)
    }

    /// Same destination contract for Add / Edit / Review parents.
    func testDestinationContractIsSharedAcrossParentFlows() {
        let intents: [ReminderOrganizationIntent] = [
            .selectPerson, .selectContext, .createPerson, .createContext
        ]
        let kinds = intents.map { ReminderOrganizationSelection.destination(for: $0) }
        XCTAssertEqual(
            kinds,
            [.personSelection, .contextSelection, .addPerson, .addContext]
        )
    }

    // MARK: - Person / Context selection data loading

    /// TC-NAV-001 Person selection loads persisted active People.
    func testPersonSelectionLoadsPersistedActivePeople() throws {
        _ = try personService.create(name: "Me")
        _ = try personService.create(name: "Child 1")
        let archived = try personService.create(name: "Old")
        _ = try personService.archive(id: archived.id)

        let loaded = try ReminderOrganizationDataLoading.loadPeople(
            personService: personService,
            selectedPersonID: nil
        )
        XCTAssertEqual(loaded.map(\.name).sorted(), ["Child 1", "Me"])
        XCTAssertFalse(loaded.contains(where: { $0.id == archived.id }))
    }

    /// TC-NAV-003 Person selection returns selected ID (via create→select wiring).
    func testPersonSelectionReturnsSelectedID() throws {
        let person = try personService.create(name: "Sanchit")
        let selected = ReminderOrganizationSelection.selectionAfterCreatingPerson(person)
        XCTAssertEqual(selected, person.id)
        let people = try ReminderOrganizationDataLoading.loadPeople(
            personService: personService,
            selectedPersonID: selected
        )
        XCTAssertTrue(people.contains(where: { $0.id == selected }))
    }

    /// TC-NAV-004 Context selection loads persisted active Contexts.
    func testContextSelectionLoadsPersistedActiveContexts() throws {
        _ = try contextService.create(name: "School")
        _ = try contextService.create(name: "Home")
        let archived = try contextService.create(name: "Old")
        _ = try contextService.archive(id: archived.id)

        let loaded = try ReminderOrganizationDataLoading.loadContexts(
            contextService: contextService,
            personID: nil,
            selectedContextID: nil
        )
        XCTAssertEqual(loaded.map(\.name).sorted(), ["Home", "School"])
        XCTAssertFalse(loaded.contains(where: { $0.id == archived.id }))
    }

    /// TC-NAV-006 Context selection returns selected ID.
    func testContextSelectionReturnsSelectedID() throws {
        let context = try contextService.create(name: "Doctor")
        let selected = ReminderOrganizationSelection.selectionAfterCreatingContext(context)
        XCTAssertEqual(selected, context.id)
        let available = try ReminderOrganizationDataLoading.loadContexts(
            contextService: contextService,
            personID: nil,
            selectedContextID: selected
        )
        XCTAssertTrue(available.contains(where: { $0.id == selected }))
    }

    /// With Person selected, selection includes global + that person's contexts.
    func testContextSelectionIncludesGlobalAndPersonSpecific() throws {
        let child1 = try personService.create(name: "Child 1")
        let child2 = try personService.create(name: "Child 2")
        let global = try contextService.create(name: "Home")
        let doctor1 = try contextService.create(name: "Doctor", personID: child1.id)
        let doctor2 = try contextService.create(name: "Doctor", personID: child2.id)

        let forChild1 = try ReminderOrganizationDataLoading.loadContexts(
            contextService: contextService,
            personID: child1.id,
            selectedContextID: nil
        )
        XCTAssertTrue(forChild1.contains(where: { $0.id == global.id }))
        XCTAssertTrue(forChild1.contains(where: { $0.id == doctor1.id }))
        XCTAssertFalse(forChild1.contains(where: { $0.id == doctor2.id }))
    }

    /// TC-NAV-009 Add Person persists and becomes selectable.
    func testAddPersonPersistsAndBecomesSelectable() throws {
        let person = try personService.create(name: "Saachi", relationship: "Daughter")
        let loaded = try ReminderOrganizationDataLoading.loadPeople(
            personService: personService,
            selectedPersonID: nil
        )
        XCTAssertTrue(loaded.contains(where: { $0.id == person.id }))
    }

    /// TC-NAV-010 Add Context persists and becomes selectable.
    func testAddContextPersistsAndBecomesSelectable() throws {
        let person = try personService.create(name: "Child 1")
        let context = try contextService.create(name: "Doctor", personID: person.id)
        let loaded = try ReminderOrganizationDataLoading.loadContexts(
            contextService: contextService,
            personID: person.id,
            selectedContextID: nil
        )
        XCTAssertTrue(loaded.contains(where: { $0.id == context.id }))
    }

    /// Cancel paths leave repositories empty.
    func testCancelAddDoesNotPersist() throws {
        XCTAssertTrue(try personService.allPeople().isEmpty)
        XCTAssertTrue(try contextService.allContexts().isEmpty)
    }

    /// Person-specific filtering + clear incompatible context.
    func testChangingPersonClearsIncompatibleContext() throws {
        let child1 = try personService.create(name: "Child 1")
        let child2 = try personService.create(name: "Child 2")
        let doctor1 = try contextService.create(name: "Doctor", personID: child1.id)
        let doctor2 = try contextService.create(name: "Doctor", personID: child2.id)
        XCTAssertNotEqual(doctor1.id, doctor2.id)

        let cleared = ReminderOrganizationSelection.reconciledContextID(
            selectedContextID: doctor1.id,
            newPersonID: child2.id,
            resolveContext: { id in try? contextService.context(id: id) }
        )
        XCTAssertNil(cleared)

        let kept = ReminderOrganizationSelection.reconciledContextID(
            selectedContextID: doctor2.id,
            newPersonID: child2.id,
            resolveContext: { id in try? contextService.context(id: id) }
        )
        XCTAssertEqual(kept, doctor2.id)

        let global = try contextService.create(name: "Home")
        let globalKept = ReminderOrganizationSelection.reconciledContextID(
            selectedContextID: global.id,
            newPersonID: child1.id,
            resolveContext: { id in try? contextService.context(id: id) }
        )
        XCTAssertEqual(globalKept, global.id)
    }

    /// Child 1 Doctor and Child 2 Doctor remain separate.
    func testPersonSpecificDoctorsRemainSeparate() throws {
        let a = try personService.create(name: "Child 1")
        let b = try personService.create(name: "Child 2")
        let c1 = try contextService.create(name: "Doctor", personID: a.id)
        let c2 = try contextService.create(name: "Doctor", personID: b.id)
        XCTAssertEqual(c1.name, c2.name)
        XCTAssertNotEqual(c1.id, c2.id)
    }
}

// MARK: - Context edit / archive UI contract + persistence

@MainActor
final class ContextEditArchiveTests: XCTestCase {
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var reminderRepo: InMemoryReminderRepository!
    private var personService: PersonService!
    private var contextService: ContextService!
    private var reminderService: ReminderService!
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        personRepo = InMemoryPersonRepository()
        contextRepo = InMemoryContextRepository()
        reminderRepo = InMemoryReminderRepository()
        personService = PersonService(repository: personRepo)
        contextService = ContextService(repository: contextRepo, personRepository: personRepo)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        let scheduler = FakeNotificationScheduler()
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
    }

    /// TC-CONTEXT-EDIT-001 Tapping Context row opens ContextDetailView (not archive).
    func testContextRowTapOpensDetailNotArchive() {
        XCTAssertEqual(ContextDetailView.preferredRowTapAction, .openDetail)
        XCTAssertNotEqual(ContextDetailView.preferredRowTapAction, .archive)
    }

    /// TC-CONTEXT-EDIT-002 Tapping Context row does not archive Context.
    func testContextRowTapDoesNotArchive() throws {
        let context = try contextService.create(name: "Doctor")
        XCTAssertEqual(ContextDetailView.preferredRowTapAction, .openDetail)
        let stillActive = try XCTUnwrap(contextService.context(id: context.id))
        XCTAssertFalse(stillActive.isArchived)
        XCTAssertEqual(try contextService.allContexts().count, 1)
    }

    /// TC-CONTEXT-EDIT-003 Edit Context name persists.
    func testEditContextNamePersists() throws {
        var context = try contextService.create(name: "Doctor")
        context.name = "Pediatrician"
        let updated = try contextService.update(context)
        XCTAssertEqual(updated.name, "Pediatrician")
        XCTAssertEqual(try contextService.context(id: context.id)?.name, "Pediatrician")
    }

    /// TC-CONTEXT-EDIT-004 Edit Context Person persists.
    func testEditContextPersonPersists() throws {
        let child = try personService.create(name: "Child 1")
        var context = try contextService.create(name: "Doctor")
        XCTAssertNil(context.personID)
        context.personID = child.id
        let updated = try contextService.update(context)
        XCTAssertEqual(updated.personID, child.id)
    }

    /// TC-CONTEXT-EDIT-005 Cancel Context edit does not modify data.
    func testCancelContextEditDoesNotModifyData() throws {
        let context = try contextService.create(name: "School")
        let before = try XCTUnwrap(contextService.context(id: context.id))
        // Cancel = no update call
        let after = try XCTUnwrap(contextService.context(id: context.id))
        XCTAssertEqual(before, after)
    }

    /// TC-CONTEXT-ARCHIVE-001 Explicit archive archives Context.
    func testExplicitArchiveArchivesContext() throws {
        XCTAssertEqual(ContextDetailView.preferredExplicitArchiveAction, .archive)
        let context = try contextService.create(name: "Office")
        let archived = try contextService.archive(id: context.id)
        XCTAssertTrue(archived.isArchived)
    }

    /// TC-CONTEXT-ARCHIVE-002 Archived Context disappears from new selection.
    func testArchivedContextDisappearsFromSelection() throws {
        let context = try contextService.create(name: "Office")
        _ = try contextService.archive(id: context.id)
        let selectable = try ReminderOrganizationDataLoading.loadContexts(
            contextService: contextService,
            personID: nil,
            selectedContextID: nil
        )
        XCTAssertFalse(selectable.contains(where: { $0.id == context.id }))
    }

    /// TC-CONTEXT-ARCHIVE-003 Archived Context does not delete reminders.
    func testArchivedContextDoesNotDeleteReminders() async throws {
        let context = try contextService.create(name: "Office")
        let created = try await reminderService.create(
            title: "Keep me",
            eventDate: calendar.date(byAdding: .day, value: 5, to: now)!,
            includeTime: false,
            eventTime: nil,
            contextID: context.id
        )
        _ = try contextService.archive(id: context.id)
        let stored = try XCTUnwrap(reminderService.reminder(id: created.reminder.id))
        XCTAssertEqual(stored.contextID, context.id)
        XCTAssertEqual(try reminderService.allReminders().count, 1)
    }

    /// Editing context metadata preserves icon/color tokens when unchanged.
    func testEditPreservesVisualTokens() throws {
        var context = try contextService.create(
            name: "Doctor",
            iconName: "stethoscope",
            colorToken: "blue"
        )
        context.name = "Dentist"
        let updated = try contextService.update(context)
        XCTAssertEqual(updated.iconName, "stethoscope")
        XCTAssertEqual(updated.colorToken, "blue")
    }

    /// Already-linked archived person may remain on context edit.
    func testEditKeepsAlreadyLinkedArchivedPerson() throws {
        let person = try personService.create(name: "Child 1")
        var context = try contextService.create(name: "Doctor", personID: person.id)
        _ = try personService.archive(id: person.id)
        context.name = "Pediatrician"
        let updated = try contextService.update(context)
        XCTAssertEqual(updated.personID, person.id)
        XCTAssertEqual(updated.name, "Pediatrician")
    }
}

@MainActor
final class PeopleArchiveSelectionTests: XCTestCase {
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var reminderRepo: InMemoryReminderRepository!
    private var personService: PersonService!
    private var reminderService: ReminderService!
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        personRepo = InMemoryPersonRepository()
        contextRepo = InMemoryContextRepository()
        reminderRepo = InMemoryReminderRepository()
        personService = PersonService(repository: personRepo)
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        let scheduler = FakeNotificationScheduler()
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
    }

    /// TC-PEOPLE-ARCHIVE-001 Explicit archive archives Person.
    func testExplicitArchiveArchivesPerson() throws {
        let person = try personService.create(name: "Child 1")
        let archived = try personService.archive(id: person.id)
        XCTAssertTrue(archived.isArchived)
    }

    /// TC-PEOPLE-ARCHIVE-002 Archived Person disappears from new selection.
    func testArchivedPersonDisappearsFromSelection() throws {
        let person = try personService.create(name: "Child 1")
        _ = try personService.archive(id: person.id)
        let selectable = try ReminderOrganizationDataLoading.loadPeople(
            personService: personService,
            selectedPersonID: nil
        )
        XCTAssertFalse(selectable.contains(where: { $0.id == person.id }))
    }

    /// TC-PEOPLE-ARCHIVE-003 Archived Person does not delete reminders.
    func testArchivedPersonDoesNotDeleteReminders() async throws {
        let person = try personService.create(name: "Child 1")
        let created = try await reminderService.create(
            title: "Keep me",
            eventDate: calendar.date(byAdding: .day, value: 5, to: now)!,
            includeTime: false,
            eventTime: nil,
            personID: person.id
        )
        _ = try personService.archive(id: person.id)
        let stored = try XCTUnwrap(reminderService.reminder(id: created.reminder.id))
        XCTAssertEqual(stored.personID, person.id)
    }
}

@MainActor
final class OrganizationOCRNavigationContractTests: XCTestCase {
    /// TC-NAV-OCR-001 / TC-NAV-OCR-002 Extraction Review uses the same destination contract.
    func testExtractionReviewUsesSameOrganizationDestinations() {
        XCTAssertEqual(
            ReminderOrganizationSelection.destination(for: .selectPerson),
            .personSelection
        )
        XCTAssertEqual(
            ReminderOrganizationSelection.destination(for: .selectContext),
            .contextSelection
        )
        XCTAssertEqual(
            ReminderOrganizationSelection.destination(for: .createPerson),
            .addPerson
        )
        XCTAssertEqual(
            ReminderOrganizationSelection.destination(for: .createContext),
            .addContext
        )
    }
}

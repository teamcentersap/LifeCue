import XCTest
@testable import LifeCue

@MainActor
final class ReminderHomeFilteringTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var reminderRepo: InMemoryReminderRepository!
    private var reminderService: ReminderService!
    private var personService: PersonService!
    private var contextService: ContextService!
    private var scheduler: FakeNotificationScheduler!

    override func setUp() {
        super.setUp()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = cal
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12))!
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

    private func makeReminder(
        title: String,
        note: String? = nil,
        day: Int = 15,
        status: ReminderStatus = .active,
        personID: UUID? = nil,
        contextID: UUID? = nil,
        rules: [ReminderRule] = [.exactAtEvent()]
    ) async throws -> Reminder {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: day))!
        let created = try await reminderService.create(
            title: title,
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: note,
            rules: rules,
            personID: personID,
            contextID: contextID
        )
        if status == .completed {
            return try await reminderService.complete(id: created.reminder.id).reminder
        }
        return created.reminder
    }

    private func names(
        _ reminders: [Reminder]
    ) -> (person: (Reminder) -> String?, context: (Reminder) -> String?) {
        let resolver = ReminderMetadataResolver(
            personService: personService,
            contextService: contextService
        )
        return ({ resolver.personName(for: $0) }, { resolver.contextName(for: $0) })
    }

    private func homeSection(for reminder: Reminder) -> ReminderHomeSection? {
        ReminderHomeClassifier(calendar: calendar, now: now).section(for: reminder)
    }

    private func filter(
        _ reminders: [Reminder],
        state: ReminderHomeFilterState
    ) -> [Reminder] {
        let n = names(reminders)
        return ReminderHomeFiltering.filter(
            reminders: reminders,
            state: state,
            personName: n.person,
            contextName: n.context,
            homeSection: { self.homeSection(for: $0) }
        )
    }

    // MARK: - Search

    /// TC-SEARCH-001
    func testSearchTitle() async throws {
        let r = try await makeReminder(title: "Doctor appointment")
        var state = ReminderHomeFilterState()
        state.searchText = "appointment"
        XCTAssertEqual(filter([r], state: state).map(\.title), ["Doctor appointment"])
    }

    /// TC-SEARCH-002
    func testSearchNote() async throws {
        let r = try await makeReminder(title: "Visit", note: "Bring reports")
        var state = ReminderHomeFilterState()
        state.searchText = "reports"
        XCTAssertEqual(filter([r], state: state).count, 1)
    }

    /// TC-SEARCH-003
    func testSearchPersonName() async throws {
        let person = try personService.create(name: "Saachi")
        let r = try await makeReminder(title: "Pickup", personID: person.id)
        var state = ReminderHomeFilterState()
        state.searchText = "saachi"
        XCTAssertEqual(filter([r], state: state).count, 1)
    }

    /// TC-SEARCH-004
    func testSearchContextName() async throws {
        let context = try contextService.create(name: "Doctor")
        let r = try await makeReminder(title: "Checkup", contextID: context.id)
        var state = ReminderHomeFilterState()
        state.searchText = "doctor"
        XCTAssertEqual(filter([r], state: state).count, 1)
    }

    /// TC-SEARCH-005
    func testSearchIsCaseInsensitive() async throws {
        let r = try await makeReminder(title: "Doctor Appointment")
        var state = ReminderHomeFilterState()
        state.searchText = "DoCtOr"
        XCTAssertEqual(filter([r], state: state).count, 1)
    }

    /// TC-SEARCH-006
    func testSearchTrimsWhitespace() async throws {
        XCTAssertEqual(ReminderHomeFiltering.normalizedQuery("  doctor  "), "doctor")
        let r = try await makeReminder(title: "Doctor")
        var state = ReminderHomeFilterState()
        state.searchText = "  doctor  "
        XCTAssertEqual(filter([r], state: state).count, 1)
    }

    /// TC-SEARCH-007
    func testNoResultState() async throws {
        let r = try await makeReminder(title: "Electricity bill")
        var state = ReminderHomeFilterState()
        state.searchText = "dentist"
        XCTAssertTrue(filter([r], state: state).isEmpty)
    }

    // MARK: - Filters

    /// TC-FILTER-001
    func testAllReturnsApplicableReminders() async throws {
        let a = try await makeReminder(title: "Overdue", day: 5)
        let b = try await makeReminder(title: "Today", day: 11)
        let c = try await makeReminder(title: "Upcoming", day: 20)
        let state = ReminderHomeFilterState()
        let result = filter([a, b, c], state: state)
        XCTAssertEqual(Set(result.map(\.title)), ["Overdue", "Today", "Upcoming"])
    }

    /// TC-FILTER-002
    func testPersonFilter() async throws {
        let child = try personService.create(name: "Child 1")
        let other = try personService.create(name: "Child 2")
        let a = try await makeReminder(title: "A", personID: child.id)
        let b = try await makeReminder(title: "B", personID: other.id)
        var state = ReminderHomeFilterState()
        state.personID = child.id
        XCTAssertEqual(filter([a, b], state: state).map(\.title), ["A"])
    }

    /// TC-FILTER-003
    func testContextFilter() async throws {
        let school = try contextService.create(name: "School")
        let doctor = try contextService.create(name: "Doctor")
        let a = try await makeReminder(title: "A", contextID: school.id)
        let b = try await makeReminder(title: "B", contextID: doctor.id)
        var state = ReminderHomeFilterState()
        state.contextID = doctor.id
        XCTAssertEqual(filter([a, b], state: state).map(\.title), ["B"])
    }

    /// TC-FILTER-004
    func testCompletedFilter() async throws {
        let active = try await makeReminder(title: "Active", day: 20)
        let done = try await makeReminder(title: "Done", day: 10, status: .completed)
        var state = ReminderHomeFilterState()
        state.status = .completed
        XCTAssertEqual(filter([active, done], state: state).map(\.title), ["Done"])
    }

    /// TC-FILTER-005
    func testUpcomingFilter() async throws {
        let overdue = try await makeReminder(title: "Past", day: 5)
        let today = try await makeReminder(title: "Today", day: 11)
        let upcoming = try await makeReminder(title: "Soon", day: 22)
        var state = ReminderHomeFilterState()
        state.status = .upcoming
        XCTAssertEqual(filter([overdue, today, upcoming], state: state).map(\.title), ["Soon"])
    }

    /// TC-FILTER-006
    func testSearchPlusPersonAND() async throws {
        let child = try personService.create(name: "Child 1")
        let other = try personService.create(name: "Child 2")
        let a = try await makeReminder(title: "Doctor visit", personID: child.id)
        let b = try await makeReminder(title: "Doctor visit", personID: other.id)
        var state = ReminderHomeFilterState()
        state.searchText = "doctor"
        state.personID = child.id
        XCTAssertEqual(filter([a, b], state: state).map(\.id), [a.id])
    }

    /// TC-FILTER-007
    func testSearchPlusContextAND() async throws {
        let doctor = try contextService.create(name: "Doctor")
        let school = try contextService.create(name: "School")
        let a = try await makeReminder(title: "Form", note: "doctor paperwork", contextID: school.id)
        let b = try await makeReminder(title: "Checkup", contextID: doctor.id)
        var state = ReminderHomeFilterState()
        state.searchText = "doctor"
        state.contextID = doctor.id
        // "Form" matches search via note but wrong context — excluded by AND.
        XCTAssertEqual(filter([a, b], state: state).map(\.title), ["Checkup"])
    }

    /// TC-FILTER-008
    func testPersonPlusContextAND() async throws {
        let child = try personService.create(name: "Child 1")
        let doctor = try contextService.create(name: "Doctor", personID: child.id)
        let school = try contextService.create(name: "School", personID: child.id)
        let a = try await makeReminder(title: "A", personID: child.id, contextID: doctor.id)
        let b = try await makeReminder(title: "B", personID: child.id, contextID: school.id)
        var state = ReminderHomeFilterState()
        state.personID = child.id
        state.contextID = doctor.id
        XCTAssertEqual(filter([a, b], state: state).map(\.title), ["A"])
    }

    /// TC-FILTER-009
    func testSearchPersonContextAND() async throws {
        let child = try personService.create(name: "Child 1")
        let doctor = try contextService.create(name: "Doctor", personID: child.id)
        let match = try await makeReminder(
            title: "Doctor appointment",
            personID: child.id,
            contextID: doctor.id
        )
        let other = try await makeReminder(title: "Doctor appointment")
        var state = ReminderHomeFilterState()
        state.searchText = "doctor"
        state.personID = child.id
        state.contextID = doctor.id
        XCTAssertEqual(filter([match, other], state: state).map(\.id), [match.id])
    }

    /// TC-FILTER-010
    func testClearFiltersRestoresFullList() async throws {
        let child = try personService.create(name: "Child 1")
        let a = try await makeReminder(title: "A", personID: child.id)
        let b = try await makeReminder(title: "B")
        var state = ReminderHomeFilterState()
        state.searchText = "A"
        state.personID = child.id
        state.status = .upcoming
        state.clearAll()
        XCTAssertEqual(Set(filter([a, b], state: state).map(\.title)), ["A", "B"])
    }

    /// TC-FILTER-011
    func testArchivedPersonNotInActiveFilterOptions() throws {
        let active = try personService.create(name: "Me")
        let archived = try personService.create(name: "Old")
        _ = try personService.archive(id: archived.id)
        let options = try personService.allPeople()
        XCTAssertTrue(options.contains(where: { $0.id == active.id }))
        XCTAssertFalse(options.contains(where: { $0.id == archived.id }))
    }

    /// TC-FILTER-012
    func testArchivedContextNotInActiveFilterOptions() throws {
        let active = try contextService.create(name: "School")
        let archived = try contextService.create(name: "Old")
        _ = try contextService.archive(id: archived.id)
        let options = try contextService.allContexts()
        XCTAssertTrue(options.contains(where: { $0.id == active.id }))
        XCTAssertFalse(options.contains(where: { $0.id == archived.id }))
    }

    /// TC-FILTER-013
    func testReminderWithArchivedPersonRemainsSearchable() async throws {
        let person = try personService.create(name: "Child 1")
        let r = try await makeReminder(title: "Keep", personID: person.id)
        _ = try personService.archive(id: person.id)
        var state = ReminderHomeFilterState()
        state.searchText = "child"
        XCTAssertEqual(filter([r], state: state).count, 1)
    }

    /// TC-FILTER-014
    func testReminderWithArchivedContextRemainsSearchable() async throws {
        let context = try contextService.create(name: "Doctor")
        let r = try await makeReminder(title: "Keep", contextID: context.id)
        _ = try contextService.archive(id: context.id)
        var state = ReminderHomeFilterState()
        state.searchText = "doctor"
        XCTAssertEqual(filter([r], state: state).count, 1)
    }

    /// TC-FILTER-015
    func testFilteringDoesNotModifyReminder() async throws {
        let r = try await makeReminder(title: "Immutable", note: "note")
        let before = r
        var state = ReminderHomeFilterState()
        state.searchText = "immutable"
        _ = filter([r], state: state)
        let after = try XCTUnwrap(reminderService.reminder(id: r.id))
        XCTAssertEqual(after, before)
    }

    /// TC-FILTER-016
    func testFilteringDoesNotModifyNotificationSchedule() async throws {
        let created = try await makeReminder(title: "Notify me", day: 20)
        let before = scheduler.scheduled
        var state = ReminderHomeFilterState()
        state.searchText = "notify"
        _ = filter([created], state: state)
        XCTAssertEqual(scheduler.scheduled.map(\.identifier), before.map(\.identifier))
        XCTAssertEqual(scheduler.scheduled.map(\.fireAt), before.map(\.fireAt))
    }

    /// TC-FILTER-017
    func testFilteringDoesNotModifyRecurrence() async throws {
        let created = try await makeReminder(
            title: "Daily",
            day: 11,
            rules: [.recurring(.daily())]
        )
        let before = created.rules
        var state = ReminderHomeFilterState()
        state.searchText = "daily"
        _ = filter([created], state: state)
        let after = try XCTUnwrap(reminderService.reminder(id: created.id))
        XCTAssertEqual(after.rules, before)
    }

    /// TC-FILTER-018
    func testFilteringDoesNotModifySnooze() async throws {
        let created = try await makeReminder(title: "Call", day: 20)
        _ = try await reminderService.snooze(id: created.id, option: .laterToday)
        let snoozed = try XCTUnwrap(reminderService.reminder(id: created.id))
        let before = snoozed.snooze
        var state = ReminderHomeFilterState()
        state.searchText = "call"
        _ = filter([snoozed], state: state)
        let after = try XCTUnwrap(reminderService.reminder(id: created.id))
        XCTAssertEqual(after.snooze, before)
    }

    /// TC-FILTER-019
    func testSixtyReminderLimitUnchanged() {
        XCTAssertEqual(ReminderSchedulingPolicy.default.maxActiveReminders, 60)
    }

    /// TC-FILTER-020
    func testOCRCreatedReminderParticipatesInSearch() async throws {
        var draft = ReminderDraft(
            title: "Dentist",
            titleWasFallback: false,
            dateState: .resolved(DateComponents(year: 2026, month: 9, day: 18)),
            timeState: .resolved(DateComponents(hour: 16, minute: 0)),
            note: "Bring reports",
            personName: nil,
            contextName: nil,
            personID: nil,
            contextID: nil,
            proposedRecurrence: nil,
            timeZoneIdentifier: calendar.timeZone.identifier,
            localeIdentifier: "en_GB",
            sourceText: "Dentist"
        )
        let created = try await reminderService.createFromConfirmedDraft(draft)
        var state = ReminderHomeFilterState()
        state.searchText = "dentist"
        XCTAssertEqual(filter([created.reminder], state: state).count, 1)
        state.searchText = "reports"
        XCTAssertEqual(filter([created.reminder], state: state).count, 1)
    }

    func testClearFiltersPreservesSearch() {
        var state = ReminderHomeFilterState()
        state.searchText = "doctor"
        state.personID = UUID()
        state.contextID = UUID()
        state.status = .completed
        state.clearFiltersPreservingSearch()
        XCTAssertEqual(state.searchText, "doctor")
        XCTAssertNil(state.personID)
        XCTAssertNil(state.contextID)
        XCTAssertEqual(state.status, .all)
    }
}

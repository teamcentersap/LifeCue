import XCTest
import SwiftData
@testable import LifeCue

/// Sprint 20 — V1 reliability + end-to-end domain/service regression coverage.
/// Production hardening for Parts A–G was verified already-correct; these tests lock behavior.
@MainActor
final class ReminderSprint20ReliabilityQATests: XCTestCase {
    private var calendar: Calendar!
    private var timeZone: TimeZone!
    private var now: Date!
    private var reminderRepo: InMemoryReminderRepository!
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var store: InMemoryBackupStoreReplacer!
    private var scheduler: FakeNotificationScheduler!
    private var reminderService: ReminderService!
    private var personService: PersonService!
    private var contextService: ContextService!
    private var deletion: OrganizationDeletionService!
    private var exportService: BackupExportService!
    private var importService: BackupImportService!

    override func setUp() {
        super.setUp()
        timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 10, minute: 0))!
        reminderRepo = InMemoryReminderRepository()
        personRepo = InMemoryPersonRepository()
        contextRepo = InMemoryContextRepository()
        store = InMemoryBackupStoreReplacer(
            reminderRepository: reminderRepo,
            personRepository: personRepo,
            contextRepository: contextRepo
        )
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
        exportService = BackupExportService(
            reminderRepository: reminderRepo,
            personRepository: personRepo,
            contextRepository: contextRepo
        )
        importService = BackupImportService(store: store, reminderService: reminderService)
        BackupExportMetadata.lastExportCreatedOnThisDevice = nil
    }

    override func tearDown() {
        BackupExportMetadata.lastExportCreatedOnThisDevice = nil
        super.tearDown()
    }

    private func eventDate(day: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day, hour: hour))!
    }

    private func encode(_ backup: LifeCueBackup) throws -> Data {
        try JSONEncoder().encode(backup)
    }

    private func emptyBackup(exportedAt: Date = Date()) -> LifeCueBackup {
        LifeCueBackup(
            format: LifeCueBackup.formatIdentifier,
            schemaVersion: LifeCueBackup.currentSchemaVersion,
            minimumReaderVersion: LifeCueBackup.currentMinimumReaderVersion,
            exportedAt: BackupJSONDate.encode(exportedAt),
            people: [],
            contexts: [],
            reminders: []
        )
    }

    // MARK: - Part A: Restore + notification result

    func testRestoreMessagesDistinguishSuccessPartialAndDoNotClaimRebuiltOnFailure() {
        let success = BackupRestorePresentation.restoreMessage(for: .success)
        let denied = BackupRestorePresentation.restoreMessage(for: .permissionDenied)
        let scheduling = BackupRestorePresentation.restoreMessage(for: .schedulingFailure)
        let persistence = BackupRestorePresentation.restoreMessage(for: .persistenceFailure)

        XCTAssertTrue(success.localizedCaseInsensitiveContains("notification"))
        XCTAssertEqual(denied, BackupRestorePresentation.restoreSuccessWithoutNotifications)
        XCTAssertEqual(scheduling, BackupRestorePresentation.restoreSuccessWithoutNotifications)
        XCTAssertEqual(persistence, BackupRestorePresentation.restoreSuccessWithoutNotifications)
        XCTAssertFalse(denied.localizedCaseInsensitiveContains("were rebuilt"))
        XCTAssertNotEqual(success, denied)
    }

    func testRestoreKeepsDataWhenNotificationPermissionDenied() async throws {
        let person = try personService.create(name: "Keep")
        _ = try await reminderService.create(
            title: "Stay",
            eventDate: eventDate(day: 20),
            includeTime: true,
            eventTime: eventDate(day: 20),
            personID: person.id
        )
        let data = try exportService.exportBackup(exportedAt: now).data
        scheduler.status = .denied

        let preview = try importService.prepareImport(from: data)
        let reconcile = try await importService.replace(with: preview)
        XCTAssertEqual(reconcile, .permissionDenied)
        XCTAssertEqual(try personService.allPeople().count, 1)
        XCTAssertEqual(try reminderService.allReminders().count, 1)
        XCTAssertEqual(
            BackupRestorePresentation.restoreMessage(for: reconcile),
            BackupRestorePresentation.restoreSuccessWithoutNotifications
        )
    }

    // MARK: - Part B: Export validation + metadata safety

    func testExportValidationFailureDoesNotUpdateLastExportOrRescheduleBackupReminder() async {
        let suite = "Sprint20.ExportFail.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let backupScheduler = BackupReminderScheduler(
            notificationScheduler: scheduler,
            defaults: defaults,
            calendar: calendar,
            clock: { self.now }
        )
        _ = await backupScheduler.enable()
        let beforeCount = scheduler.scheduledApp.count

        let vm = BackupRestoreViewModel(
            exportService: FailingBackupExportService(),
            importService: NoOpBackupImportService(),
            backupReminderScheduler: backupScheduler
        )
        BackupExportMetadata.lastExportCreatedOnThisDevice = nil
        vm.prepareExport()

        XCTAssertNotNil(vm.errorMessage)
        XCTAssertNil(BackupExportMetadata.lastExportCreatedOnThisDevice)
        XCTAssertFalse(vm.showExporter)
        XCTAssertEqual(scheduler.scheduledApp.count, beforeCount)
    }

    func testCancelledExportDoesNotUpdateLastExportMetadata() {
        let vm = BackupRestoreViewModel(
            exportService: exportService,
            importService: importService,
            backupReminderScheduler: nil
        )
        BackupExportMetadata.lastExportCreatedOnThisDevice = nil
        vm.didFinishExport(result: .failure(NSError(domain: "cancel", code: 0)))
        XCTAssertNil(BackupExportMetadata.lastExportCreatedOnThisDevice)
        XCTAssertNil(vm.lastExportCreatedOnThisDevice)
        XCTAssertNil(vm.infoMessage)
    }

    func testSuccessfulExportUpdatesLastExportMetadata() {
        let vm = BackupRestoreViewModel(
            exportService: exportService,
            importService: importService
        )
        BackupExportMetadata.lastExportCreatedOnThisDevice = nil
        vm.exportCounts = BackupInventoryCounts(reminders: 0, people: 0, contexts: 0)
        let url = URL(fileURLWithPath: "/tmp/lifecue-sprint20-export.lifecuebackup")
        vm.didFinishExport(result: .success(url))
        XCTAssertNotNil(BackupExportMetadata.lastExportCreatedOnThisDevice)
        XCTAssertNotNil(vm.lastExportCreatedOnThisDevice)
        XCTAssertNotNil(vm.infoMessage)
    }

    // MARK: - Part C: Import safety gaps

    func testEmptyBackupFileRejectedWithoutMutation() throws {
        try reminderRepo.save(
            Reminder(
                title: "Existing",
                eventDate: DateComponents(year: 2026, month: 8, day: 20),
                timeZoneIdentifier: timeZone.identifier,
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )
        XCTAssertThrowsError(try importService.prepareImport(from: Data())) { error in
            XCTAssertEqual(error as? BackupValidationError, .invalidJSON)
        }
        XCTAssertEqual(try reminderRepo.fetchAll().count, 1)
    }

    func testUnsupportedOldSchemaRejected() throws {
        var backup = emptyBackup(exportedAt: now)
        backup.schemaVersion = 0
        XCTAssertThrowsError(try BackupValidator.decodeAndValidate(data: try encode(backup))) { error in
            XCTAssertEqual(error as? BackupValidationError, .unsupportedSchema)
        }
    }

    func testInvalidExportedAtDateRejected() throws {
        var backup = emptyBackup(exportedAt: now)
        backup.exportedAt = "not-a-date"
        XCTAssertThrowsError(try BackupValidator.validateExport(backup)) { error in
            XCTAssertEqual(error as? BackupValidationError, .invalidDate)
        }
    }

    func testInvalidTimezoneRejected() throws {
        var backup = emptyBackup(exportedAt: now)
        backup.reminders = [
            LifeCueBackupReminder(
                id: UUID(),
                title: "Bad TZ",
                eventDate: LifeCueBackupDateComponents(year: 2026, month: 8, day: 20),
                eventTime: LifeCueBackupTimeComponents(hour: 9, minute: 0),
                timeZoneIdentifier: "Not/A_Real_Zone",
                note: nil,
                personID: nil,
                contextID: nil,
                status: ReminderStatus.active.rawValue,
                rules: [
                    LifeCueBackupRule(
                        id: UUID(),
                        ruleType: ReminderRuleType.exactAtEvent.rawValue,
                        offsetValue: nil,
                        offsetUnit: nil,
                        enabled: true,
                        recurrence: nil,
                        dateWindow: nil
                    )
                ],
                snooze: nil,
                createdAt: BackupJSONDate.encode(now),
                updatedAt: BackupJSONDate.encode(now),
                completedAt: nil
            )
        ]
        XCTAssertThrowsError(try BackupValidator.validateExport(backup)) { error in
            XCTAssertEqual(error as? BackupValidationError, .invalidTimeZone)
        }
    }

    func testInvalidRuleRejected() throws {
        var backup = emptyBackup(exportedAt: now)
        backup.reminders = [
            LifeCueBackupReminder(
                id: UUID(),
                title: "Bad rule",
                eventDate: LifeCueBackupDateComponents(year: 2026, month: 8, day: 20),
                eventTime: nil,
                timeZoneIdentifier: timeZone.identifier,
                note: nil,
                personID: nil,
                contextID: nil,
                status: ReminderStatus.active.rawValue,
                rules: [
                    LifeCueBackupRule(
                        id: UUID(),
                        ruleType: "not-a-rule",
                        offsetValue: nil,
                        offsetUnit: nil,
                        enabled: true,
                        recurrence: nil,
                        dateWindow: nil
                    )
                ],
                snooze: nil,
                createdAt: BackupJSONDate.encode(now),
                updatedAt: BackupJSONDate.encode(now),
                completedAt: nil
            )
        ]
        XCTAssertThrowsError(try BackupValidator.validateExport(backup)) { error in
            XCTAssertEqual(error as? BackupValidationError, .invalidRule)
        }
    }

    func testMalformedUUIDJSONRejectedWithoutMutation() throws {
        try personRepo.save(
            Person(id: UUID(), name: "Keep", createdAt: now, updatedAt: now)
        )
        let json = """
        {
          "format": "LifeCueBackup",
          "schemaVersion": 1,
          "minimumReaderVersion": 1,
          "exportedAt": "\(BackupJSONDate.encode(now))",
          "people": [{"id":"not-a-uuid","name":"X","isArchived":false,"createdAt":"\(BackupJSONDate.encode(now))","updatedAt":"\(BackupJSONDate.encode(now))"}],
          "contexts": [],
          "reminders": []
        }
        """
        XCTAssertThrowsError(try importService.prepareImport(from: Data(json.utf8))) { error in
            XCTAssertEqual(error as? BackupValidationError, .invalidJSON)
        }
        XCTAssertEqual(try personRepo.fetchAll().count, 1)
    }

    func testValidBackupPrepareDoesNotMutateUntilReplace() throws {
        try reminderRepo.save(
            Reminder(
                title: "Current",
                eventDate: DateComponents(year: 2026, month: 8, day: 21),
                timeZoneIdentifier: timeZone.identifier,
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )
        let data = try encode(emptyBackup(exportedAt: now))
        _ = try importService.prepareImport(from: data)
        XCTAssertEqual(try reminderRepo.fetchAll().count, 1)
        XCTAssertEqual(try reminderRepo.fetchAll().first?.title, "Current")
    }

    // MARK: - Part D: Corrupt reminder isolation

    func testMultipleValidPlusOneCorruptLoadsValidOnly() throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let repo = SwiftDataReminderRepository(modelContext: context)

        for title in ["A", "B", "C"] {
            try repo.save(
                Reminder(
                    title: title,
                    eventDate: DateComponents(year: 2026, month: 8, day: 20),
                    eventTime: DateComponents(hour: 9, minute: 0),
                    timeZoneIdentifier: timeZone.identifier,
                    rules: [.exactAtEvent()],
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        let corruptTitle = "B"
        let descriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate { $0.title == corruptTitle }
        )
        let corrupt = try XCTUnwrap(try context.fetch(descriptor).first)
        corrupt.statusRaw = "broken"
        try context.save()

        let outcome = try repo.fetchAllOutcome()
        XCTAssertEqual(Set(outcome.reminders.map(\.title)), Set(["A", "C"]))
        XCTAssertEqual(outcome.skippedCorruptRecordIDs.count, 1)
    }

    func testMultipleCorruptRecordsDoNotBlankValidReminders() throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let repo = SwiftDataReminderRepository(modelContext: context)
        let service = ReminderService(
            repository: repo,
            notificationScheduler: FakeNotificationScheduler(),
            calendar: calendar,
            clock: { self.now }
        )

        for title in ["Good", "Bad1", "Bad2"] {
            try repo.save(
                Reminder(
                    title: title,
                    eventDate: DateComponents(year: 2026, month: 8, day: 22),
                    eventTime: DateComponents(hour: 9, minute: 0),
                    timeZoneIdentifier: timeZone.identifier,
                    rules: [.exactAtEvent()],
                    createdAt: now,
                    updatedAt: now
                )
            )
        }
        for title in ["Bad1", "Bad2"] {
            let descriptor = FetchDescriptor<ReminderRecord>(
                predicate: #Predicate { $0.title == title }
            )
            let record = try XCTUnwrap(try context.fetch(descriptor).first)
            record.statusRaw = "nope"
            try context.save()
        }

        let sections = try service.homeSections()
        let loaded = sections.values.flatMap { $0 }
        XCTAssertEqual(loaded.map(\.title), ["Good"])
        XCTAssertEqual(service.lastFetchSkippedCorruptRecordCount, 2)
    }

    func testAllValidRemindersLoadWithoutCorruptWarning() throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let repo = SwiftDataReminderRepository(modelContext: context)
        let service = ReminderService(
            repository: repo,
            notificationScheduler: FakeNotificationScheduler(),
            calendar: calendar,
            clock: { self.now }
        )
        try repo.save(
            Reminder(
                title: "Only",
                eventDate: DateComponents(year: 2026, month: 8, day: 12),
                eventTime: DateComponents(hour: 11, minute: 0),
                timeZoneIdentifier: timeZone.identifier,
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )
        let vm = ReminderListViewModel(service: service)
        vm.load()
        XCTAssertNil(vm.corruptRecordsWarning)
        XCTAssertFalse(vm.isEmpty)
    }

    func testCorruptRecordsWarningIsNonTechnical() throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let repo = SwiftDataReminderRepository(modelContext: context)
        let service = ReminderService(
            repository: repo,
            notificationScheduler: FakeNotificationScheduler(),
            calendar: calendar,
            clock: { self.now }
        )
        try repo.save(
            Reminder(
                title: "Valid",
                eventDate: DateComponents(year: 2026, month: 8, day: 20),
                eventTime: DateComponents(hour: 9, minute: 0),
                timeZoneIdentifier: timeZone.identifier,
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )
        try repo.save(
            Reminder(
                title: "Corrupt",
                eventDate: DateComponents(year: 2026, month: 8, day: 21),
                eventTime: DateComponents(hour: 9, minute: 0),
                timeZoneIdentifier: timeZone.identifier,
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )
        let corruptTitle = "Corrupt"
        let descriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate { $0.title == corruptTitle }
        )
        let corrupt = try XCTUnwrap(try context.fetch(descriptor).first)
        corrupt.rulesJSON = Data("{broken".utf8)
        try context.save()

        let vm = ReminderListViewModel(service: service)
        vm.load()
        let warning = try XCTUnwrap(vm.corruptRecordsWarning)
        XCTAssertTrue(warning.localizedCaseInsensitiveContains("couldn't be loaded"))
        XCTAssertFalse(warning.localizedCaseInsensitiveContains("SwiftData"))
        XCTAssertFalse(warning.localizedCaseInsensitiveContains("JSON"))
        XCTAssertEqual(vm.upcoming.count + vm.today.count + vm.overdue.count, 1)
    }

    // MARK: - Part E / F regression contracts

    func testCalendarRefreshTokenStillAcceptedAfterRestoreStyleReload() async throws {
        let displayCalendar = MonthCalendarGridBuilder.makeCalendar(timeZone: timeZone)
        let vm = CalendarMonthViewModel(
            calendarService: FakeCalendarService(status: .fullAccess, events: []),
            reminderService: reminderService,
            displayCalendar: displayCalendar,
            clock: { self.now }
        )
        try reminderRepo.save(
            Reminder(
                title: "Before",
                eventDate: DateComponents(year: 2026, month: 8, day: 12),
                eventTime: DateComponents(hour: 11, minute: 0),
                timeZoneIdentifier: timeZone.identifier,
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )
        await vm.loadInitial()
        XCTAssertTrue(vm.selectedReminders.contains(where: { $0.title == "Before" }))

        reminderRepo.replaceStorage([:])
        try reminderRepo.save(
            Reminder(
                title: "AfterRestore",
                eventDate: DateComponents(year: 2026, month: 8, day: 12),
                eventTime: DateComponents(hour: 11, minute: 0),
                timeZoneIdentifier: timeZone.identifier,
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )
        await vm.refreshOnBecomeActive()
        XCTAssertTrue(vm.selectedReminders.contains(where: { $0.title == "AfterRestore" }))
        XCTAssertFalse(vm.selectedReminders.contains(where: { $0.title == "Before" }))
    }

    func testPersistenceFailureBlocksWithoutInMemoryFallback() {
        struct Boom: Error {}
        let result = LifeCueAppBootstrap.make { throw Boom() }
        guard case .failure(let error) = result else {
            return XCTFail("Expected failure")
        }
        XCTAssertEqual(error, .persistentContainerUnavailable)
        XCTAssertFalse(PersistenceFailurePresentation.message.isEmpty)
    }

    // MARK: - Flow 1: Basic reminder

    func testFlowBasicReminderCreateCompleteCleansNotifications() async throws {
        let created = try await reminderService.create(
            title: "One-time",
            eventDate: eventDate(day: 25),
            includeTime: true,
            eventTime: eventDate(day: 25, hour: 16),
            note: "Bring ID"
        )
        XCTAssertEqual(try reminderService.allReminders().count, 1)
        XCTAssertFalse(scheduler.scheduled.isEmpty)
        let idsBefore = Set(scheduler.scheduled.map(\.identifier))

        _ = try await reminderService.complete(id: created.reminder.id)
        XCTAssertEqual(try reminderService.reminder(id: created.reminder.id)?.status, .completed)
        XCTAssertTrue(idsBefore.isDisjoint(with: Set(scheduler.scheduled.map(\.identifier)))
            || scheduler.scheduled.isEmpty
            || scheduler.cancelledIdentifiers.contains(where: { idsBefore.contains($0) }))
    }

    // MARK: - Flow 2: Date-only reminder

    func testFlowDateOnlyReminderUsesDefaultTimeAndSchedules() async throws {
        let created = try await reminderService.create(
            title: "Date only",
            eventDate: eventDate(day: 28),
            includeTime: false,
            eventTime: nil
        )
        let defaultTime = LifeCueSettings.defaultTimeForNewDateOnlyReminder()
        XCTAssertEqual(created.reminder.eventTime?.hour, defaultTime.hour)
        XCTAssertEqual(created.reminder.eventTime?.minute, defaultTime.minute)
        let reconcile = await reminderService.reconcileAllNotifications()
        XCTAssertEqual(reconcile, .success)
        XCTAssertFalse(scheduler.scheduled.isEmpty)
    }

    // MARK: - Flow 3: Recurring reminder edit clears stale schedule

    func testFlowWeeklyRecurrenceEditDoesNotLeaveOldSchedule() async throws {
        let created = try await reminderService.create(
            title: "Weekly",
            eventDate: now,
            includeTime: true,
            eventTime: now,
            rules: [.recurring(.weekly(weekdays: [2, 4]))],
            timeZoneIdentifier: timeZone.identifier
        )
        let oldIDs = Set(scheduler.scheduled.map(\.identifier))
        XCTAssertFalse(oldIDs.isEmpty)

        var updated = created.reminder
        updated.rules = [.recurring(.weekly(weekdays: [5]))]
        _ = try await reminderService.update(updated)

        let newIDs = Set(scheduler.scheduled.map(\.identifier))
        XCTAssertFalse(newIDs.isEmpty)
        // Old notification identifiers must not remain pending.
        XCTAssertTrue(oldIDs.isDisjoint(with: newIDs) || scheduler.cancelledIdentifiers.contains(where: oldIDs.contains))
        XCTAssertEqual(try reminderService.allReminders().count, 1)
    }

    // MARK: - Flow 4: People archive / unarchive / delete

    func testFlowPersonArchiveUnarchiveDeletePreservesThenCleansReminders() async throws {
        let person = try personService.create(name: "John")
        let context = try contextService.create(name: "Doctor", personID: person.id)
        let reminder = try await reminderService.create(
            title: "Checkup",
            eventDate: eventDate(day: 30),
            includeTime: true,
            eventTime: eventDate(day: 30),
            personID: person.id,
            contextID: context.id
        )

        _ = try personService.archive(id: person.id)
        XCTAssertEqual(try reminderService.reminder(id: reminder.reminder.id)?.personID, person.id)
        _ = try personService.unarchive(id: person.id)
        XCTAssertEqual(try reminderService.reminder(id: reminder.reminder.id)?.id, reminder.reminder.id)
        XCTAssertNotNil(try contextService.context(id: context.id))
        XCTAssertFalse(try contextService.context(id: context.id)?.isArchived == true)

        try await deletion.permanentlyDeletePerson(id: person.id)
        XCTAssertNil(try personService.person(id: person.id))
        XCTAssertNil(try contextService.context(id: context.id))
        XCTAssertNil(try reminderService.reminder(id: reminder.reminder.id))
        XCTAssertTrue(try reminderService.allReminders().allSatisfy { $0.personID != person.id })
    }

    // MARK: - Flow 5: Context archive / unarchive / delete

    func testFlowContextArchiveUnarchiveDeleteKeepsPersonAndUnrelatedReminders() async throws {
        let person = try personService.create(name: "Owner")
        let context = try contextService.create(name: "School", personID: person.id)
        let linked = try await reminderService.create(
            title: "Linked",
            eventDate: eventDate(day: 26),
            includeTime: true,
            eventTime: eventDate(day: 26),
            personID: person.id,
            contextID: context.id
        )
        let unrelated = try await reminderService.create(
            title: "Unrelated",
            eventDate: eventDate(day: 27),
            includeTime: true,
            eventTime: eventDate(day: 27)
        )

        _ = try contextService.archive(id: context.id)
        _ = try contextService.unarchive(id: context.id)
        XCTAssertEqual(try reminderService.reminder(id: linked.reminder.id)?.contextID, context.id)
        XCTAssertEqual(try personService.person(id: person.id)?.id, person.id)

        try await deletion.permanentlyDeleteContext(id: context.id)
        XCTAssertNil(try contextService.context(id: context.id))
        XCTAssertNil(try reminderService.reminder(id: linked.reminder.id))
        XCTAssertNotNil(try personService.person(id: person.id))
        XCTAssertNotNil(try reminderService.reminder(id: unrelated.reminder.id))
    }

    // MARK: - Flow 6: Backup / restore end-to-end

    func testFlowBackupRestorePreservesIDsRelationshipsAndReconciles() async throws {
        let person = try personService.create(name: "Child")
        let global = try contextService.create(name: "General")
        let personal = try contextService.create(name: "Health", personID: person.id)
        let active = try await reminderService.create(
            title: "Active",
            eventDate: eventDate(day: 18),
            includeTime: true,
            eventTime: eventDate(day: 18, hour: 8),
            note: "With note",
            rules: [.recurring(.weekly(weekdays: [2, 3])), .exactAtEvent()],
            timeZoneIdentifier: "America/New_York",
            personID: person.id,
            contextID: personal.id
        )
        let completed = try await reminderService.create(
            title: "Done",
            eventDate: eventDate(day: 5),
            includeTime: false,
            eventTime: nil
        )
        _ = try await reminderService.complete(id: completed.reminder.id)
        _ = try personService.archive(id: person.id)
        _ = try contextService.archive(id: personal.id)

        let export = try exportService.exportBackup(exportedAt: now)
        try BackupValidator.validateExport(export.backup)

        // Contaminate live data.
        try await reminderService.delete(id: active.reminder.id)
        _ = try personService.create(name: "Intruder")

        let preview = try importService.prepareImport(from: export.data)
        let reconcile = try await importService.replace(with: preview)
        XCTAssertEqual(reconcile, .success)

        XCTAssertEqual(try personService.person(id: person.id)?.name, "Child")
        XCTAssertTrue(try personService.person(id: person.id)?.isArchived == true)
        XCTAssertNotNil(try contextService.context(id: global.id))
        XCTAssertTrue(try contextService.context(id: personal.id)?.isArchived == true)
        XCTAssertEqual(try contextService.context(id: personal.id)?.personID, person.id)

        let restoredActive = try XCTUnwrap(try reminderService.reminder(id: active.reminder.id))
        XCTAssertEqual(restoredActive.note, "With note")
        XCTAssertEqual(restoredActive.timeZoneIdentifier, "America/New_York")
        XCTAssertEqual(restoredActive.personID, person.id)
        XCTAssertEqual(restoredActive.contextID, personal.id)
        XCTAssertEqual(try reminderService.reminder(id: completed.reminder.id)?.status, .completed)
        XCTAssertFalse(try personService.allPeople().contains(where: { $0.name == "Intruder" }))
        XCTAssertFalse(scheduler.scheduled.isEmpty)
    }

    // MARK: - Flow 7: Image extraction safety

    func testFlowAmbiguousExtractionCannotConfirmWithoutResolution() {
        var draft = ReminderDraft(
            title: "Event",
            titleWasFallback: false,
            dateState: .ambiguous(
                candidates: [
                    DateComponents(year: 2026, month: 5, day: 6),
                    DateComponents(year: 2026, month: 6, day: 5)
                ],
                rawSnippet: "05/06/2026"
            ),
            timeState: .missing,
            note: nil,
            personName: nil,
            contextName: nil,
            personID: nil,
            contextID: nil,
            proposedRecurrence: nil,
            timeZoneIdentifier: timeZone.identifier,
            localeIdentifier: "en_US",
            sourceText: ""
        )
        XCTAssertThrowsError(try ReminderDraftConverter.makeConfirmedInput(from: draft))
        draft.dateState = .resolved(DateComponents(year: 2026, month: 6, day: 5))
        XCTAssertNoThrow(try ReminderDraftConverter.makeConfirmedInput(from: draft))
    }

    func testFlowEmptyOCRSourceDoesNotCrashExtractionPipeline() {
        let empty = ReminderDraft(
            title: "",
            titleWasFallback: true,
            dateState: .missing,
            timeState: .missing,
            note: nil,
            personName: nil,
            contextName: nil,
            personID: nil,
            contextID: nil,
            proposedRecurrence: nil,
            timeZoneIdentifier: timeZone.identifier,
            localeIdentifier: "en_GB",
            sourceText: ""
        )
        XCTAssertThrowsError(try ReminderDraftConverter.makeConfirmedInput(from: empty))
    }

    // MARK: - Flow 8: Notification routing isolation

    func testFlowReminderAndBackupNotificationIdentifiersRemainIsolated() async throws {
        _ = try await reminderService.create(
            title: "Normal",
            eventDate: eventDate(day: 19),
            includeTime: true,
            eventTime: eventDate(day: 19)
        )
        let reminderIDs = scheduler.scheduled.map(\.identifier)
        XCTAssertFalse(reminderIDs.isEmpty)
        XCTAssertFalse(reminderIDs.contains(BackupReminderNotification.identifier))
        XCTAssertNil(NotificationIdentifier.reminderID(from: BackupReminderNotification.identifier))
        XCTAssertTrue(
            BackupReminderNotification.isBackupReminder(
                requestIdentifier: BackupReminderNotification.identifier,
                userInfo: [:]
            )
        )
        XCTAssertFalse(
            BackupReminderNotification.isBackupReminder(
                requestIdentifier: reminderIDs[0],
                userInfo: [:]
            )
        )
    }

    // MARK: - Flow 9: Home filtering AND + clear

    func testFlowHomeFiltersCombineWithANDAndClearAll() async throws {
        let person = try personService.create(name: "FilterPerson")
        let context = try contextService.create(name: "FilterContext")
        let match = try await reminderService.create(
            title: "Match",
            eventDate: eventDate(day: 15),
            includeTime: true,
            eventTime: eventDate(day: 15),
            personID: person.id,
            contextID: context.id
        )
        let other = try await reminderService.create(
            title: "Other",
            eventDate: eventDate(day: 16),
            includeTime: true,
            eventTime: eventDate(day: 16)
        )

        let resolver = ReminderMetadataResolver(
            personService: personService,
            contextService: contextService
        )
        let classifier = ReminderHomeClassifier(calendar: calendar, now: now)
        let all = [match.reminder, other.reminder]
        var state = ReminderHomeFilterState()
        state.searchText = "Match"
        state.personID = person.id
        state.contextID = context.id
        let filtered = ReminderHomeFiltering.filter(
            reminders: all,
            state: state,
            personName: { resolver.personName(for: $0) },
            contextName: { resolver.contextName(for: $0) },
            homeSection: { classifier.section(for: $0) }
        )
        XCTAssertEqual(filtered.map(\.title), ["Match"])

        state.clearAll()
        let cleared = ReminderHomeFiltering.filter(
            reminders: all,
            state: state,
            personName: { resolver.personName(for: $0) },
            contextName: { resolver.contextName(for: $0) },
            homeSection: { classifier.section(for: $0) }
        )
        XCTAssertEqual(cleared.count, 2)
    }

    // MARK: - Flow 10 / Part I: Settings + permissions

    func testFlowSettingsAppearanceAndDefaultReminderTimeContracts() {
        UserDefaults.standard.removeObject(forKey: LifeCueSettings.appearanceKey)
        UserDefaults.standard.removeObject(forKey: LifeCueSettings.defaultReminderTimeKey)
        defer {
            UserDefaults.standard.removeObject(forKey: LifeCueSettings.appearanceKey)
            UserDefaults.standard.removeObject(forKey: LifeCueSettings.defaultReminderTimeKey)
        }
        XCTAssertEqual(LifeCueSettings.appearance, .system)
        LifeCueSettings.appearance = .dark
        XCTAssertEqual(LifeCueSettings.appearance, .dark)
        XCTAssertEqual(LifeCueSettings.defaultReminderTime.hour, 9)
    }

    func testPermissionMatrixNotificationLabelsAndOpenSettings() {
        XCTAssertEqual(NotificationAuthorizationDisplay.label(for: .authorized), "Allowed")
        XCTAssertEqual(NotificationAuthorizationDisplay.label(for: .denied), "Denied")
        XCTAssertEqual(NotificationAuthorizationDisplay.label(for: .notDetermined), "Not Determined")
        XCTAssertEqual(NotificationAuthorizationDisplay.label(for: .unsupported), "Restricted")
        XCTAssertTrue(NotificationAuthorizationDisplay.showsOpenSettings(for: .denied))
        XCTAssertTrue(NotificationAuthorizationDisplay.showsOpenSettings(for: .unsupported))
        XCTAssertFalse(NotificationAuthorizationDisplay.showsOpenSettings(for: .authorized))
        XCTAssertFalse(NotificationAuthorizationDisplay.showsOpenSettings(for: .notDetermined))
    }

    func testPermissionDeniedCreateDoesNotCrashAndKeepsReminder() async throws {
        scheduler.status = .denied
        let result = try await reminderService.create(
            title: "Saved without notifs",
            eventDate: eventDate(day: 29),
            includeTime: true,
            eventTime: eventDate(day: 29)
        )
        XCTAssertEqual(result.scheduleOutcome, .permissionDenied)
        XCTAssertEqual(try reminderService.allReminders().count, 1)
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testCalendarDeniedStatusDoesNotCrashMonthViewModel() async {
        let vm = CalendarMonthViewModel(
            calendarService: FakeCalendarService(status: .denied, events: []),
            reminderService: reminderService,
            displayCalendar: MonthCalendarGridBuilder.makeCalendar(timeZone: timeZone),
            clock: { self.now }
        )
        await vm.refreshOnBecomeActive()
        XCTAssertEqual(vm.authorizationStatus, .denied)
    }

    // MARK: - Part J: Backup Reminder permission denial

    func testBackupReminderEnableWithDeniedPermissionDoesNotCrash() async {
        let suite = "Sprint20.BackupReminder.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        scheduler.status = .denied
        let backupScheduler = BackupReminderScheduler(
            notificationScheduler: scheduler,
            defaults: defaults,
            calendar: calendar,
            clock: { self.now }
        )
        let status = await backupScheduler.enable()
        XCTAssertEqual(status, .denied)
    }
}

// MARK: - Test doubles

@MainActor
private final class FailingBackupExportService: BackupExportServing {
    func exportBackup(exportedAt: Date) throws -> (backup: LifeCueBackup, data: Data, counts: BackupInventoryCounts) {
        throw BackupValidationError.wrongFormat
    }
}

@MainActor
private final class NoOpBackupImportService: BackupImportServing {
    func prepareImport(from data: Data) throws -> BackupImportPreview {
        throw BackupValidationError.unreadable
    }

    func replace(with preview: BackupImportPreview) async throws -> NotificationReconcileResult {
        .success
    }
}

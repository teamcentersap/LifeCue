import XCTest
import SwiftData
@testable import LifeCue

@MainActor
final class ReminderSprint14BackupTests: XCTestCase {
    private var calendar: Calendar!
    private var timeZone: TimeZone!
    private var now: Date!
    private var reminderRepo: InMemoryReminderRepository!
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var store: InMemoryBackupStoreReplacer!
    private var scheduler: FakeNotificationScheduler!
    private var reminderService: ReminderService!
    private var exportService: BackupExportService!
    private var importService: BackupImportService!

    override func setUp() {
        super.setUp()
        timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 10, minute: 30))!
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
            calendar: calendar,
            clock: { self.now }
        )
        exportService = BackupExportService(
            reminderRepository: reminderRepo,
            personRepository: personRepo,
            contextRepository: contextRepo
        )
        importService = BackupImportService(store: store, reminderService: reminderService)
    }

    // MARK: - Helpers

    private func seedScenario() throws -> (Person, ReminderContext, Reminder) {
        let person = Person(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            name: "Child 1",
            createdAt: now,
            updatedAt: now
        )
        try personRepo.save(person)
        let context = ReminderContext(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            name: "Doctor",
            personID: person.id,
            createdAt: now,
            updatedAt: now
        )
        try contextRepo.save(context)
        let window = ReminderDateWindow(
            startDate: DateComponents(year: 2026, month: 8, day: 15),
            endDate: DateComponents(year: 2026, month: 8, day: 20)
        )
        let recurrence = ReminderRecurrence.daily()
        let rule = ReminderRule.recurring(recurrence, window: window)
        let reminder = Reminder(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            title: "Doctor appointment",
            eventDate: DateComponents(year: 2026, month: 8, day: 15),
            eventTime: DateComponents(hour: 16, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            personID: person.id,
            contextID: context.id,
            status: .active,
            rules: [rule, .exactAtEvent()],
            createdAt: now,
            updatedAt: now
        )
        try reminderRepo.save(reminder)
        return (person, context, reminder)
    }

    private func encode(_ backup: LifeCueBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(backup)
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else {
            throw NSError(domain: "test", code: 1)
        }
        return dict
    }

    // MARK: - Export

    /// TC-BACKUP-001
    func test001_ExportEmptyDatabase() throws {
        let result = try exportService.exportBackup(exportedAt: now)
        XCTAssertEqual(result.counts.reminders, 0)
        XCTAssertEqual(result.counts.people, 0)
        XCTAssertEqual(result.counts.contexts, 0)
        XCTAssertEqual(result.backup.format, "LifeCueBackup")
        XCTAssertEqual(result.backup.schemaVersion, 1)
    }

    /// TC-BACKUP-002
    func test002_ExportOneReminder() throws {
        try reminderRepo.save(Reminder(
            title: "Solo",
            eventDate: DateComponents(year: 2026, month: 9, day: 1),
            timeZoneIdentifier: "Asia/Kolkata",
            createdAt: now,
            updatedAt: now
        ))
        let result = try exportService.exportBackup(exportedAt: now)
        XCTAssertEqual(result.backup.reminders.count, 1)
        XCTAssertEqual(result.backup.reminders[0].title, "Solo")
    }

    /// TC-BACKUP-003
    func test003_ExportRecurringReminder() throws {
        let rule = ReminderRule.recurring(.weekly(weekdays: [2, 4]))
        try reminderRepo.save(Reminder(
            title: "Weekly",
            eventDate: DateComponents(year: 2026, month: 8, day: 12),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [rule],
            createdAt: now,
            updatedAt: now
        ))
        let exported = try exportService.exportBackup(exportedAt: now).backup.reminders[0]
        XCTAssertEqual(exported.rules.first?.recurrence?.frequency, "weekly")
        XCTAssertEqual(exported.rules.first?.recurrence?.weekdays, [2, 4])
    }

    /// TC-BACKUP-004
    func test004_ExportDateWindowRecurrence() throws {
        let (_, _, reminder) = try seedScenario()
        let exported = try exportService.exportBackup(exportedAt: now).backup.reminders.first {
            $0.id == reminder.id
        }
        let window = exported?.rules.first(where: { $0.dateWindow != nil })?.dateWindow
        XCTAssertEqual(window?.startDate.day, 15)
        XCTAssertEqual(window?.endDate.day, 20)
    }

    /// TC-BACKUP-005
    func test005_ExportSnoozedReminder() throws {
        let until = now.addingTimeInterval(3600)
        try reminderRepo.save(Reminder(
            title: "Snoozed",
            eventDate: DateComponents(year: 2026, month: 8, day: 12),
            eventTime: DateComponents(hour: 18, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.exactAtEvent()],
            snooze: ReminderSnoozeState(until: until),
            createdAt: now,
            updatedAt: now
        ))
        let snooze = try exportService.exportBackup(exportedAt: now).backup.reminders[0].snooze
        XCTAssertEqual(BackupJSONDate.decode(snooze!.until), until)
        XCTAssertTrue(snooze!.until.hasSuffix("Z") || snooze!.until.contains("+00:00") || snooze!.until.contains("Z"))
    }

    /// TC-BACKUP-006
    func test006_ExportCompletedReminder() throws {
        try reminderRepo.save(Reminder(
            title: "Done",
            eventDate: DateComponents(year: 2026, month: 8, day: 1),
            timeZoneIdentifier: "Asia/Kolkata",
            status: .completed,
            createdAt: now,
            updatedAt: now,
            completedAt: now
        ))
        let exported = try exportService.exportBackup(exportedAt: now).backup.reminders[0]
        XCTAssertEqual(exported.status, "completed")
        XCTAssertNotNil(exported.completedAt)
    }

    /// TC-BACKUP-007 / 008 / 009 / 010
    func test007to010_ExportPeopleContextsAndLinks() throws {
        let (person, context, reminder) = try seedScenario()
        let backup = try exportService.exportBackup(exportedAt: now).backup
        XCTAssertEqual(backup.people.map(\.id), [person.id])
        XCTAssertEqual(backup.contexts.map(\.id), [context.id])
        XCTAssertEqual(backup.contexts[0].personID, person.id)
        let exportedReminder = backup.reminders.first { $0.id == reminder.id }
        XCTAssertEqual(exportedReminder?.personID, person.id)
        XCTAssertEqual(exportedReminder?.contextID, context.id)
    }

    // MARK: - Round trip

    /// TC-BACKUP-011…018, 037, 038, 043, 044
    func test011to018_RoundTripPreservesDomain() async throws {
        let (person, context, reminder) = try seedScenario()
        let snoozeUntil = now.addingTimeInterval(7200)
        var snoozed = reminder
        snoozed.snooze = ReminderSnoozeState(until: snoozeUntil)
        try reminderRepo.save(snoozed)

        let archivedPerson = Person(
            id: UUID(),
            name: "Archived Child",
            isArchived: true,
            createdAt: now,
            updatedAt: now
        )
        try personRepo.save(archivedPerson)
        let archivedContext = ReminderContext(
            id: UUID(),
            name: "Old School",
            personID: archivedPerson.id,
            isArchived: true,
            createdAt: now,
            updatedAt: now
        )
        try contextRepo.save(archivedContext)

        let completed = Reminder(
            id: UUID(),
            title: "Completed one",
            eventDate: DateComponents(year: 2026, month: 7, day: 1),
            timeZoneIdentifier: "America/New_York",
            status: .completed,
            createdAt: now,
            updatedAt: now,
            completedAt: now
        )
        try reminderRepo.save(completed)

        let data = try exportService.exportBackup(exportedAt: now).data

        // Contaminate store then replace from backup.
        try reminderRepo.save(Reminder(
            title: "Should disappear",
            eventDate: DateComponents(year: 2026, month: 1, day: 1),
            timeZoneIdentifier: "Asia/Kolkata",
            createdAt: now,
            updatedAt: now
        ))

        let preview = try importService.prepareImport(from: data)
        try await importService.replace(with: preview)

        let restoredReminders = try reminderRepo.fetchAll()
        let restoredPeople = try personRepo.fetchAll()
        let restoredContexts = try contextRepo.fetchAll()

        XCTAssertEqual(restoredReminders.count, 2)
        XCTAssertEqual(Set(restoredPeople.map(\.id)), Set([person.id, archivedPerson.id]))
        XCTAssertEqual(Set(restoredContexts.map(\.id)), Set([context.id, archivedContext.id]))

        let restored = try XCTUnwrap(restoredReminders.first { $0.id == reminder.id })
        XCTAssertEqual(restored.title, "Doctor appointment")
        XCTAssertEqual(restored.timeZoneIdentifier, "Asia/Kolkata")
        XCTAssertEqual(restored.eventTime?.hour, 16)
        XCTAssertEqual(restored.personID, person.id)
        XCTAssertEqual(restored.contextID, context.id)
        XCTAssertEqual(restored.snooze?.until, snoozeUntil)
        XCTAssertEqual(
            restored.rules.first(where: { $0.ruleType == .recurring })?.recurrence?.frequency,
            .daily
        )
        XCTAssertEqual(
            restored.rules.first(where: { $0.dateWindow != nil })?.dateWindow?.startDate.day,
            15
        )

        XCTAssertTrue(try XCTUnwrap(restoredPeople.first { $0.id == archivedPerson.id }).isArchived)
        XCTAssertTrue(try XCTUnwrap(restoredContexts.first { $0.id == archivedContext.id }).isArchived)
        XCTAssertEqual(try XCTUnwrap(restoredReminders.first { $0.id == completed.id }).status, .completed)

        // Date-only completed reminder had nil time — still nil after restore.
        XCTAssertNil(try XCTUnwrap(restoredReminders.first { $0.id == completed.id }).eventTime)
        XCTAssertEqual(
            try XCTUnwrap(restoredReminders.first { $0.id == completed.id }).timeZoneIdentifier,
            "America/New_York"
        )
    }

    /// TC-BACKUP-019 / 020 / 021
    func test019to021_PlatformSpecificDataExcluded() throws {
        _ = try seedScenario()
        let data = try exportService.exportBackup(exportedAt: now).data
        let json = String(data: data, encoding: .utf8)!
        XCTAssertFalse(json.contains("lifecue.reminder."))
        XCTAssertFalse(json.lowercased().contains("unnotification"))
        XCTAssertFalse(json.lowercased().contains("ekevent"))
        XCTAssertFalse(json.lowercased().contains("eventkit"))
        XCTAssertFalse(json.contains("sourceText"))
        XCTAssertFalse(json.lowercased().contains("ocr"))
        let dict = try jsonObject(from: data)
        XCTAssertNil(dict["notifications"])
        XCTAssertNil(dict["calendarEvents"])
        XCTAssertNil(dict["images"])
    }

    // MARK: - Validation

    /// TC-BACKUP-022
    func test022_InvalidJSONRejected() {
        XCTAssertThrowsError(try importService.prepareImport(from: Data("not-json".utf8))) { error in
            XCTAssertEqual(error as? BackupValidationError, .invalidJSON)
        }
    }

    /// TC-BACKUP-023
    func test023_WrongFormatRejected() throws {
        var backup = LifeCueBackupMapper.makeBackup(people: [], contexts: [], reminders: [], exportedAt: now)
        backup.format = "NotLifeCue"
        let data = try encode(backup)
        XCTAssertThrowsError(try importService.prepareImport(from: data)) { error in
            XCTAssertEqual(error as? BackupValidationError, .wrongFormat)
        }
    }

    /// TC-BACKUP-024 / 040
    func test024_UnsupportedFutureSchemaRejected() throws {
        var backup = LifeCueBackupMapper.makeBackup(people: [], contexts: [], reminders: [], exportedAt: now)
        backup.schemaVersion = 99
        backup.minimumReaderVersion = 99
        let data = try encode(backup)
        XCTAssertThrowsError(try importService.prepareImport(from: data)) { error in
            XCTAssertEqual(error as? BackupValidationError, .unsupportedSchema)
        }
        XCTAssertEqual(BackupUserFacingError.from(BackupValidationError.unsupportedSchema), .unsupportedSchema)
    }

    /// TC-BACKUP-025
    func test025_MissingRequiredFieldRejected() throws {
        let json = """
        {"format":"LifeCueBackup","schemaVersion":1,"minimumReaderVersion":1,"exportedAt":"\(BackupJSONDate.encode(now))","people":[],"contexts":[]}
        """
        XCTAssertThrowsError(try importService.prepareImport(from: Data(json.utf8))) { error in
            XCTAssertEqual(error as? BackupValidationError, .missingRequiredField)
        }
    }

    /// TC-BACKUP-026 / 027
    func test026_027_DuplicateIDsRejected() throws {
        let person = Person(id: UUID(), name: "A", createdAt: now, updatedAt: now)
        var backup = LifeCueBackupMapper.makeBackup(
            people: [person, person],
            contexts: [],
            reminders: [],
            exportedAt: now
        )
        XCTAssertThrowsError(try BackupValidator.validateContents(backup)) { error in
            XCTAssertEqual(error as? BackupValidationError, .duplicatePersonID)
        }

        let reminder = Reminder(
            id: UUID(),
            title: "R",
            eventDate: DateComponents(year: 2026, month: 8, day: 12),
            timeZoneIdentifier: "Asia/Kolkata",
            createdAt: now,
            updatedAt: now
        )
        backup = LifeCueBackupMapper.makeBackup(
            people: [],
            contexts: [],
            reminders: [reminder, reminder],
            exportedAt: now
        )
        XCTAssertThrowsError(try BackupValidator.validateContents(backup)) { error in
            XCTAssertEqual(error as? BackupValidationError, .duplicateReminderID)
        }
    }

    /// TC-BACKUP-028 / 029 / 030
    func test028to030_InvalidRelationshipsRejected() throws {
        let personA = Person(id: UUID(), name: "A", createdAt: now, updatedAt: now)
        let personB = Person(id: UUID(), name: "B", createdAt: now, updatedAt: now)
        let context = ReminderContext(
            id: UUID(),
            name: "Doctor",
            personID: personB.id,
            createdAt: now,
            updatedAt: now
        )
        let reminder = Reminder(
            title: "Mismatch",
            eventDate: DateComponents(year: 2026, month: 8, day: 15),
            timeZoneIdentifier: "Asia/Kolkata",
            personID: personA.id,
            contextID: context.id,
            createdAt: now,
            updatedAt: now
        )
        let backup = LifeCueBackupMapper.makeBackup(
            people: [personA, personB],
            contexts: [context],
            reminders: [reminder],
            exportedAt: now
        )
        XCTAssertThrowsError(try BackupValidator.validateContents(backup)) { error in
            XCTAssertEqual(error as? BackupValidationError, .personContextMismatch)
        }

        let orphanPersonReminder = Reminder(
            title: "Orphan person",
            eventDate: DateComponents(year: 2026, month: 8, day: 15),
            timeZoneIdentifier: "Asia/Kolkata",
            personID: UUID(),
            createdAt: now,
            updatedAt: now
        )
        let orphanBackup = LifeCueBackupMapper.makeBackup(
            people: [],
            contexts: [],
            reminders: [orphanPersonReminder],
            exportedAt: now
        )
        XCTAssertThrowsError(try BackupValidator.validateContents(orphanBackup)) { error in
            XCTAssertEqual(error as? BackupValidationError, .invalidPersonReference)
        }

        let orphanContextReminder = Reminder(
            title: "Orphan context",
            eventDate: DateComponents(year: 2026, month: 8, day: 15),
            timeZoneIdentifier: "Asia/Kolkata",
            contextID: UUID(),
            createdAt: now,
            updatedAt: now
        )
        let orphanContextBackup = LifeCueBackupMapper.makeBackup(
            people: [],
            contexts: [],
            reminders: [orphanContextReminder],
            exportedAt: now
        )
        XCTAssertThrowsError(try BackupValidator.validateContents(orphanContextBackup)) { error in
            XCTAssertEqual(error as? BackupValidationError, .invalidContextReference)
        }
    }

    /// TC-BACKUP-031
    func test031_FailedValidationDoesNotModifyData() throws {
        try reminderRepo.save(Reminder(
            title: "Keep",
            eventDate: DateComponents(year: 2026, month: 8, day: 12),
            timeZoneIdentifier: "Asia/Kolkata",
            createdAt: now,
            updatedAt: now
        ))
        XCTAssertThrowsError(try importService.prepareImport(from: Data("{}".utf8)))
        XCTAssertEqual(try reminderRepo.fetchAll().count, 1)
        XCTAssertEqual(try reminderRepo.fetchAll().first?.title, "Keep")
    }

    /// TC-BACKUP-032
    func test032_CancelImportDoesNotModifyData() throws {
        _ = try seedScenario()
        let before = try reminderRepo.fetchAll().count
        let data = try exportService.exportBackup(exportedAt: now).data
        _ = try importService.prepareImport(from: data)
        // Cancel = do not call replace.
        XCTAssertEqual(try reminderRepo.fetchAll().count, before)
    }

    /// TC-BACKUP-033 / 034
    func test033_034_ExplicitReplaceOnly() async throws {
        _ = try seedScenario()
        let data = try exportService.exportBackup(exportedAt: now).data
        try reminderRepo.save(Reminder(
            title: "Extra",
            eventDate: DateComponents(year: 2026, month: 8, day: 13),
            timeZoneIdentifier: "Asia/Kolkata",
            createdAt: now,
            updatedAt: now
        ))
        XCTAssertEqual(try reminderRepo.fetchAll().count, 2)
        let preview = try importService.prepareImport(from: data)
        // Without replace, data stays.
        XCTAssertEqual(try reminderRepo.fetchAll().count, 2)
        try await importService.replace(with: preview)
        XCTAssertEqual(try reminderRepo.fetchAll().count, 1)
        XCTAssertEqual(try reminderRepo.fetchAll().first?.title, "Doctor appointment")
    }

    /// TC-BACKUP-035 / 036
    func test035_036_NotificationsRebuiltWithNewIDs() async throws {
        _ = try seedScenario()
        let data = try exportService.exportBackup(exportedAt: now).data
        let preview = try importService.prepareImport(from: data)
        scheduler.reset()
        try await importService.replace(with: preview)
        let reminderID = try XCTUnwrap(preview.snapshot.reminders.first?.id)
        XCTAssertFalse(scheduler.scheduled.isEmpty)
        for request in scheduler.scheduled {
            XCTAssertTrue(request.identifier.hasPrefix("lifecue.reminder.\(reminderID.uuidString)"))
            XCTAssertTrue(request.identifier.contains(".g"))
        }
        let json = String(data: data, encoding: .utf8)!
        for request in scheduler.scheduled {
            XCTAssertFalse(json.contains(request.identifier))
        }
    }

    /// TC-BACKUP-037 date-only 9am behavior via engine after restore
    func test037_DateOnlyPreservesDefaultNineAMBehavior() async throws {
        let dateOnly = Reminder(
            id: UUID(),
            title: "Date only",
            eventDate: DateComponents(year: 2026, month: 8, day: 20),
            eventTime: nil,
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.exactAtEvent()],
            createdAt: now,
            updatedAt: now
        )
        try reminderRepo.save(dateOnly)
        let data = try exportService.exportBackup(exportedAt: now).data
        try await importService.replace(with: try importService.prepareImport(from: data))
        let restored = try XCTUnwrap(reminderRepo.fetch(id: dateOnly.id))
        XCTAssertNil(restored.eventTime)
        let engine = ReminderRuleEngine(policy: .default, calendar: calendar)
        let occurrences = engine.occurrences(for: restored, now: now, onlyFuture: false)
        let exact = try XCTUnwrap(occurrences.first { $0.ruleType == .exactAtEvent })
        let reminderCal = restored.calendarInStoredTimeZone(template: calendar)
        let comps = reminderCal.dateComponents([.hour, .minute], from: exact.fireAt)
        XCTAssertEqual(comps.hour, 9)
        XCTAssertEqual(comps.minute, 0)
    }

    /// TC-BACKUP-039
    func test039_SupportedV1Migrates() throws {
        let backup = LifeCueBackupMapper.makeBackup(people: [], contexts: [], reminders: [], exportedAt: now)
        let migrated = try BackupMigrator.migrateToCurrent(backup)
        XCTAssertEqual(migrated.schemaVersion, 1)
        _ = try BackupValidator.decodeAndValidate(data: try encode(backup))
    }

    /// TC-BACKUP-041
    func test041_NoLoginRequired() throws {
        let result = try exportService.exportBackup(exportedAt: now)
        _ = try importService.prepareImport(from: result.data)
        // Reached without credentials / account APIs.
        XCTAssertEqual(result.backup.format, LifeCueBackup.formatIdentifier)
    }

    /// TC-BACKUP-042
    func test042_ExportDoesNotMutateReminders() throws {
        let (_, _, reminder) = try seedScenario()
        let before = try reminderRepo.fetch(id: reminder.id)
        _ = try exportService.exportBackup(exportedAt: now)
        let after = try reminderRepo.fetch(id: reminder.id)
        XCTAssertEqual(before, after)
    }

    func testReplaceFailureLeavesCurrentData() async throws {
        _ = try seedScenario()
        let data = try exportService.exportBackup(exportedAt: now).data
        let preview = try importService.prepareImport(from: data)
        store.shouldFailReplace = true
        do {
            try await importService.replace(with: preview)
            XCTFail("Expected failure")
        } catch {
            XCTAssertEqual(try reminderRepo.fetchAll().first?.title, "Doctor appointment")
        }
    }

    func testSwiftDataAtomicReplaceRoundTrip() throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let reminderRepository = SwiftDataReminderRepository(modelContext: context)
        let personRepository = SwiftDataPersonRepository(modelContext: context)
        let contextRepository = SwiftDataContextRepository(modelContext: context)
        let replacer = SwiftDataBackupStoreReplacer(modelContext: context)

        let person = Person(name: "Child 1", createdAt: now, updatedAt: now)
        try personRepository.save(person)
        let doctor = ReminderContext(name: "Doctor", personID: person.id, createdAt: now, updatedAt: now)
        try contextRepository.save(doctor)
        let reminder = Reminder(
            title: "Doctor appointment",
            eventDate: DateComponents(year: 2026, month: 8, day: 15),
            eventTime: DateComponents(hour: 16, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            personID: person.id,
            contextID: doctor.id,
            rules: [.recurring(.daily(), window: ReminderDateWindow(
                startDate: DateComponents(year: 2026, month: 8, day: 15),
                endDate: DateComponents(year: 2026, month: 8, day: 20)
            ))],
            createdAt: now,
            updatedAt: now
        )
        try reminderRepository.save(reminder)

        let export = BackupExportService(
            reminderRepository: reminderRepository,
            personRepository: personRepository,
            contextRepository: contextRepository
        )
        let data = try export.exportBackup(exportedAt: now).data
        let (_, snapshot) = try BackupValidator.decodeAndValidate(data: data)

        // Contaminate then atomic replace.
        try reminderRepository.save(Reminder(
            title: "Noise",
            eventDate: DateComponents(year: 2026, month: 1, day: 1),
            timeZoneIdentifier: "Asia/Kolkata",
            createdAt: now,
            updatedAt: now
        ))
        XCTAssertEqual(try reminderRepository.fetchAll().count, 2)

        try replacer.replaceAll(with: snapshot)
        XCTAssertEqual(try reminderRepository.fetchAll().count, 1)
        XCTAssertEqual(try reminderRepository.fetchAll().first?.id, reminder.id)
        XCTAssertEqual(try personRepository.fetchAll().first?.id, person.id)
        XCTAssertEqual(try contextRepository.fetchAll().first?.personID, person.id)
    }
}
import XCTest
import SwiftData
@testable import LifeCue

@MainActor
final class ReminderSprint17ReliabilityTests: XCTestCase {
    private var calendar: Calendar!
    private var now: Date!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 10))!
    }

    // MARK: - Part A: Persistence bootstrap

    func testPersistentContainerBootstrapSucceeds() {
        let result = LifeCueAppBootstrap.make {
            try LifeCuePersistence.makeContainer(inMemory: true)
        }
        guard case .success(let composition) = result else {
            return XCTFail("Expected bootstrap success")
        }
        XCTAssertNotNil(composition.reminderService)
    }

    func testPersistentContainerFailureDoesNotUseInMemoryFallback() {
        struct BootstrapFailure: Error {}
        let result = LifeCueAppBootstrap.make { throw BootstrapFailure() }
        guard case .failure(let error) = result else {
            return XCTFail("Expected bootstrap failure")
        }
        XCTAssertEqual(error, .persistentContainerUnavailable)
    }

    func testPersistenceFailurePresentationExists() {
        XCTAssertFalse(PersistenceFailurePresentation.message.isEmpty)
        XCTAssertTrue(PersistenceFailurePresentation.message.localizedCaseInsensitiveContains("couldn't open"))
    }

    // MARK: - Part B: Restore reconciliation result

    func testRestoreSuccessMessageWhenNotificationsReconcile() {
        XCTAssertEqual(
            BackupRestorePresentation.restoreMessage(for: .success),
            BackupRestorePresentation.restoreSuccessWithNotifications
        )
    }

    func testRestorePartialMessageWhenNotificationsDenied() {
        XCTAssertEqual(
            BackupRestorePresentation.restoreMessage(for: .permissionDenied),
            BackupRestorePresentation.restoreSuccessWithoutNotifications
        )
    }

    func testRestorePartialMessageWhenSchedulingFails() {
        XCTAssertEqual(
            BackupRestorePresentation.restoreMessage(for: .schedulingFailure),
            BackupRestorePresentation.restoreSuccessWithoutNotifications
        )
    }

    func testReplaceReturnsReconcileResultWithoutThrowingOnPermissionDenied() async throws {
        let reminderRepo = InMemoryReminderRepository()
        let personRepo = InMemoryPersonRepository()
        let contextRepo = InMemoryContextRepository()
        let store = InMemoryBackupStoreReplacer(
            reminderRepository: reminderRepo,
            personRepository: personRepo,
            contextRepository: contextRepo
        )
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .denied
        let service = ReminderService(repository: reminderRepo, notificationScheduler: scheduler, calendar: calendar)
        let export = BackupExportService(
            reminderRepository: reminderRepo,
            personRepository: personRepo,
            contextRepository: contextRepo
        )
        let importService = BackupImportService(store: store, reminderService: service)

        let reminder = Reminder(
            title: "Test",
            eventDate: DateComponents(year: 2026, month: 8, day: 20),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.exactAtEvent()],
            createdAt: now,
            updatedAt: now
        )
        try reminderRepo.save(reminder)
        let data = try export.exportBackup(exportedAt: now).data
        let preview = try importService.prepareImport(from: data)

        let reconcile = try await importService.replace(with: preview)
        XCTAssertEqual(reconcile, .permissionDenied)
    }

    // MARK: - Part C: Export validation

    func testExportValidatesBeforeEncoding() throws {
        let reminderRepo = InMemoryReminderRepository()
        let export = BackupExportService(
            reminderRepository: reminderRepo,
            personRepository: InMemoryPersonRepository(),
            contextRepository: InMemoryContextRepository()
        )
        let reminder = Reminder(
            title: "Valid",
            eventDate: DateComponents(year: 2026, month: 8, day: 20),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.exactAtEvent()],
            createdAt: now,
            updatedAt: now
        )
        try reminderRepo.save(reminder)
        XCTAssertNoThrow(try export.exportBackup(exportedAt: now))
    }

    func testValidateExportRejectsWrongFormat() {
        let backup = LifeCueBackup(
            format: "wrong-format",
            schemaVersion: 1,
            minimumReaderVersion: 1,
            exportedAt: BackupJSONDate.encode(now),
            people: [],
            contexts: [],
            reminders: []
        )
        XCTAssertThrowsError(try BackupValidator.validateExport(backup))
    }

    // MARK: - Part D: Corrupt record isolation

    func testOneCorruptReminderDoesNotBlockValidReminder() throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let repo = SwiftDataReminderRepository(modelContext: context)

        try repo.save(
            Reminder(
                title: "Valid",
                eventDate: DateComponents(year: 2026, month: 8, day: 20),
                eventTime: DateComponents(hour: 9, minute: 0),
                timeZoneIdentifier: "Asia/Kolkata",
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
                timeZoneIdentifier: "Asia/Kolkata",
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )

        let corruptTitle = "Corrupt"
        let corruptDescriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate { $0.title == corruptTitle }
        )
        let corruptRecord = try XCTUnwrap(try context.fetch(corruptDescriptor).first)
        let corruptID = corruptRecord.id
        corruptRecord.statusRaw = "invalid-status"
        try context.save()

        let outcome = try repo.fetchAllOutcome()
        XCTAssertEqual(outcome.reminders.count, 1)
        XCTAssertEqual(outcome.reminders.first?.title, "Valid")
        XCTAssertEqual(outcome.skippedCorruptRecordIDs, [corruptID])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ReminderRecord>()), 2)
    }

    func testInvalidRulesJSONDoesNotBlankHome() throws {
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
                title: "Loads",
                eventDate: DateComponents(year: 2026, month: 8, day: 20),
                eventTime: DateComponents(hour: 9, minute: 0),
                timeZoneIdentifier: "Asia/Kolkata",
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )
        try repo.save(
            Reminder(
                title: "Bad rules",
                eventDate: DateComponents(year: 2026, month: 8, day: 22),
                eventTime: DateComponents(hour: 9, minute: 0),
                timeZoneIdentifier: "Asia/Kolkata",
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )

        let badRulesTitle = "Bad rules"
        let badRulesDescriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate { $0.title == badRulesTitle }
        )
        let badRulesRecord = try XCTUnwrap(try context.fetch(badRulesDescriptor).first)
        badRulesRecord.rulesJSON = Data("{not-json".utf8)
        try context.save()

        let sections = try service.homeSections()
        let all = sections.values.flatMap { $0 }
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.title, "Loads")
        XCTAssertEqual(service.lastFetchSkippedCorruptRecordCount, 1)
    }

    func testInvalidStatusDoesNotSilentlyBecomeActive() throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let repo = SwiftDataReminderRepository(modelContext: context)

        try repo.save(
            Reminder(
                title: "Bad status",
                eventDate: DateComponents(year: 2026, month: 8, day: 20),
                eventTime: DateComponents(hour: 9, minute: 0),
                timeZoneIdentifier: "Asia/Kolkata",
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )

        let badStatusTitle = "Bad status"
        let badStatusDescriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate { $0.title == badStatusTitle }
        )
        let record = try XCTUnwrap(try context.fetch(badStatusDescriptor).first)
        record.statusRaw = "not-active"
        try context.save()

        XCTAssertThrowsError(try record.asDomain()) { error in
            XCTAssertEqual(error as? ReminderRecordConversionError, .invalidStatus)
        }
        let outcome = try repo.fetchAllOutcome()
        XCTAssertTrue(outcome.reminders.isEmpty)
        XCTAssertEqual(outcome.skippedCorruptRecordIDs.count, 1)
    }

    func testReconcileStillProcessesValidRemindersWhenOneRecordIsCorrupt() async throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let repo = SwiftDataReminderRepository(modelContext: context)
        let scheduler = FakeNotificationScheduler()
        let service = ReminderService(
            repository: repo,
            notificationScheduler: scheduler,
            calendar: calendar,
            clock: { self.now }
        )

        try repo.save(
            Reminder(
                title: "Notify me",
                eventDate: DateComponents(year: 2026, month: 8, day: 20),
                eventTime: DateComponents(hour: 9, minute: 0),
                timeZoneIdentifier: "Asia/Kolkata",
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
                timeZoneIdentifier: "Asia/Kolkata",
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )

        let corruptTitle = "Corrupt"
        let corruptDescriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate { $0.title == corruptTitle }
        )
        let corruptRecord = try XCTUnwrap(try context.fetch(corruptDescriptor).first)
        corruptRecord.statusRaw = "broken"
        try context.save()

        let result = await service.reconcileAllNotifications()
        XCTAssertEqual(result, .success)
        XCTAssertFalse(scheduler.scheduled.isEmpty)
    }

    // MARK: - Part E: Import size protection

    func testImportBelowSizeLimitAccepted() throws {
        XCTAssertNoThrow(try BackupValidator.validateImportFileSize(1024))
    }

    func testImportAboveSizeLimitRejected() {
        let tooLarge = BackupValidator.maxImportFileSizeBytes + 1
        XCTAssertThrowsError(try BackupValidator.validateImportFileSize(tooLarge)) { error in
            XCTAssertEqual(error as? BackupValidationError, .fileTooLarge)
        }
    }

    func testOversizedImportDoesNotMutateExistingData() throws {
        let reminderRepo = InMemoryReminderRepository()
        let export = BackupExportService(
            reminderRepository: reminderRepo,
            personRepository: InMemoryPersonRepository(),
            contextRepository: InMemoryContextRepository()
        )
        let importService = BackupImportService(
            store: InMemoryBackupStoreReplacer(
                reminderRepository: reminderRepo,
                personRepository: InMemoryPersonRepository(),
                contextRepository: InMemoryContextRepository()
            ),
            reminderService: ReminderService(
                repository: reminderRepo,
                notificationScheduler: FakeNotificationScheduler(),
                calendar: calendar
            )
        )

        let reminder = Reminder(
            title: "Keep me",
            eventDate: DateComponents(year: 2026, month: 8, day: 20),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.exactAtEvent()],
            createdAt: now,
            updatedAt: now
        )
        try reminderRepo.save(reminder)

        var oversized = try export.exportBackup(exportedAt: now).data
        oversized.append(contentsOf: Data(repeating: 0, count: BackupValidator.maxImportFileSizeBytes))

        XCTAssertThrowsError(try importService.prepareImport(from: oversized))
        XCTAssertEqual(try reminderRepo.fetchAll().first?.title, "Keep me")
    }

    // MARK: - Part F: Calendar refresh token contract

    func testCalendarMonthViewAcceptsDataRefreshToken() {
        let view = CalendarMonthView(
            calendarService: FakeCalendarService(),
            reminderService: ReminderService(
                repository: InMemoryReminderRepository(),
                notificationScheduler: FakeNotificationScheduler(),
                calendar: calendar
            ),
            personService: PersonService(repository: InMemoryPersonRepository()),
            contextService: ContextService(
                repository: InMemoryContextRepository(),
                personRepository: InMemoryPersonRepository()
            ),
            dataRefreshToken: UUID()
        )
        XCTAssertNotNil(view.body)
    }

    func testCalendarReloadsRemindersAfterRestoreStyleRefresh() async throws {
        // Contract: selectedReminders is day-scoped to the ViewModel's selected day
        // (defaults to clock()'s calendar day). Use that day so assertions match production.
        let displayCalendar = MonthCalendarGridBuilder.makeCalendar(
            timeZone: TimeZone(identifier: "Asia/Kolkata")!
        )
        let selectedDay = CalendarDayComponents(year: 2026, month: 8, day: 12)
        let repo = InMemoryReminderRepository()
        let service = ReminderService(
            repository: repo,
            notificationScheduler: FakeNotificationScheduler(),
            calendar: calendar,
            clock: { self.now }
        )
        let vm = CalendarMonthViewModel(
            calendarService: FakeCalendarService(),
            reminderService: service,
            displayCalendar: displayCalendar,
            clock: { self.now }
        )
        XCTAssertEqual(vm.selectedDay, selectedDay)

        try repo.save(
            Reminder(
                title: "Before",
                eventDate: DateComponents(year: 2026, month: 8, day: 12),
                eventTime: DateComponents(hour: 9, minute: 0),
                timeZoneIdentifier: "Asia/Kolkata",
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )
        await vm.loadInitial()
        XCTAssertEqual(vm.selectedReminders.map(\.title), ["Before"])
        XCTAssertTrue(vm.reminderIndicatorDays.contains(selectedDay))

        try repo.replaceStorage([:])
        try repo.save(
            Reminder(
                title: "After restore",
                eventDate: DateComponents(year: 2026, month: 8, day: 12),
                eventTime: DateComponents(hour: 10, minute: 0),
                timeZoneIdentifier: "Asia/Kolkata",
                rules: [.exactAtEvent()],
                createdAt: now,
                updatedAt: now
            )
        )
        await vm.refreshOnBecomeActive()
        XCTAssertEqual(vm.selectedReminders.map(\.title), ["After restore"])
        XCTAssertFalse(vm.selectedReminders.map(\.title).contains("Before"))
        XCTAssertTrue(vm.reminderIndicatorDays.contains(selectedDay))
    }

    // MARK: - Part H: SwiftData atomic restore rollback

    func testSwiftDataReplaceRollbackPreservesOriginalData() throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let reminderRepository = SwiftDataReminderRepository(modelContext: context)
        let replacer = SwiftDataBackupStoreReplacer(modelContext: context)

        let original = Reminder(
            title: "Original",
            eventDate: DateComponents(year: 2026, month: 8, day: 15),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: "Asia/Kolkata",
            rules: [.exactAtEvent()],
            createdAt: now,
            updatedAt: now
        )
        try reminderRepository.save(original)

        let replacement = BackupDomainSnapshot(
            people: [],
            contexts: [],
            reminders: [
                Reminder(
                    title: "Replacement",
                    eventDate: DateComponents(year: 2026, month: 9, day: 1),
                    eventTime: DateComponents(hour: 12, minute: 0),
                    timeZoneIdentifier: "Asia/Kolkata",
                    rules: [.exactAtEvent()],
                    createdAt: now,
                    updatedAt: now
                )
            ]
        )

        replacer.testWillSave = { throw BackupValidationError.replaceFailed }

        XCTAssertThrowsError(try replacer.replaceAll(with: replacement)) { error in
            XCTAssertEqual(error as? BackupValidationError, .replaceFailed)
        }

        let reminders = try reminderRepository.fetchAll()
        XCTAssertEqual(reminders.count, 1)
        XCTAssertEqual(reminders.first?.title, "Original")
    }
}

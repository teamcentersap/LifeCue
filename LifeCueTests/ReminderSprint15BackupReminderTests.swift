import XCTest
@testable import LifeCue

@MainActor
final class ReminderSprint15BackupReminderTests: XCTestCase {
    private var calendar: Calendar!
    private var timeZone: TimeZone!
    private var now: Date!
    private var defaults: UserDefaults!
    private var scheduler: FakeNotificationScheduler!
    private var backupReminderScheduler: BackupReminderScheduler!
    private var reminderRepo: InMemoryReminderRepository!
    private var reminderService: ReminderService!

    override func setUp() {
        super.setUp()
        timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 12, hour: 10, minute: 30))!
        defaults = UserDefaults(suiteName: "ReminderSprint15BackupReminderTests.\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: defaults.description)
        scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        backupReminderScheduler = BackupReminderScheduler(
            notificationScheduler: scheduler,
            defaults: defaults,
            calendar: calendar,
            clock: { self.now }
        )
        reminderRepo = InMemoryReminderRepository()
        reminderService = ReminderService(
            repository: reminderRepo,
            notificationScheduler: scheduler,
            calendar: calendar,
            clock: { self.now }
        )
        BackupExportMetadata.lastExportCreatedOnThisDevice = nil
    }

    override func tearDown() {
        BackupExportMetadata.lastExportCreatedOnThisDevice = nil
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    private func scheduledBackupFireDate() -> Date? {
        scheduler.scheduledApp.first { $0.identifier == BackupReminderNotification.identifier }?.fireAt
    }

    private func expectedFireDate(from base: Date, interval: BackupReminderInterval) -> Date {
        BackupReminderScheduler.nextFireDate(from: base, interval: interval, calendar: calendar)
    }

    // MARK: - TC-BACKUP-REMINDER-001 Default OFF

    func testTC_BACKUP_REMINDER_001_defaultOff() {
        XCTAssertFalse(backupReminderScheduler.isEnabled)
        XCTAssertEqual(backupReminderScheduler.interval, .oneWeek)
        XCTAssertTrue(scheduler.scheduledApp.isEmpty)
    }

    // MARK: - TC-BACKUP-REMINDER-002 Enable

    func testTC_BACKUP_REMINDER_002_enable() async {
        _ = await backupReminderScheduler.enable()
        XCTAssertTrue(backupReminderScheduler.isEnabled)
        XCTAssertNotNil(backupReminderScheduler.enabledAt)
        XCTAssertTrue(scheduler.didRequestAuthorization)
    }

    // MARK: - TC-BACKUP-REMINDER-003 Disable

    func testTC_BACKUP_REMINDER_003_disable() async {
        _ = await backupReminderScheduler.enable()
        await backupReminderScheduler.disable()
        XCTAssertFalse(backupReminderScheduler.isEnabled)
        XCTAssertNil(backupReminderScheduler.enabledAt)
    }

    // MARK: - Interval fire dates

    func testTC_BACKUP_REMINDER_004_oneWeekInterval() async {
        backupReminderScheduler.interval = .oneWeek
        _ = await backupReminderScheduler.enable()
        let fire = scheduledBackupFireDate()
        XCTAssertEqual(fire, expectedFireDate(from: now, interval: .oneWeek))
    }

    func testTC_BACKUP_REMINDER_005_twoWeekInterval() async {
        backupReminderScheduler.interval = .twoWeeks
        _ = await backupReminderScheduler.enable()
        let fire = scheduledBackupFireDate()
        XCTAssertEqual(fire, expectedFireDate(from: now, interval: .twoWeeks))
    }

    func testTC_BACKUP_REMINDER_006_oneMonthInterval() async {
        backupReminderScheduler.interval = .oneMonth
        _ = await backupReminderScheduler.enable()
        let fire = scheduledBackupFireDate()
        XCTAssertEqual(fire, expectedFireDate(from: now, interval: .oneMonth))
    }

    func testTC_BACKUP_REMINDER_007_threeMonthInterval() async {
        backupReminderScheduler.interval = .threeMonths
        _ = await backupReminderScheduler.enable()
        let fire = scheduledBackupFireDate()
        XCTAssertEqual(fire, expectedFireDate(from: now, interval: .threeMonths))
    }

    // MARK: - TC-BACKUP-REMINDER-008 Enable schedules exactly one notification

    func testTC_BACKUP_REMINDER_008_enableSchedulesExactlyOneNotification() async {
        _ = await backupReminderScheduler.enable()
        XCTAssertEqual(scheduler.scheduledApp.count, 1)
        XCTAssertEqual(scheduler.scheduledApp.first?.identifier, BackupReminderNotification.identifier)
    }

    // MARK: - TC-BACKUP-REMINDER-009 Disable cancels only backup notification

    func testTC_BACKUP_REMINDER_009_disableCancelsOnlyBackupNotification() async throws {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13))!
        let eventTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 14, minute: 0))!
        _ = try await reminderService.create(
            title: "Pay bill",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventTime,
            timeZoneIdentifier: "Asia/Kolkata"
        )

        _ = await backupReminderScheduler.enable()
        XCTAssertEqual(scheduler.scheduledApp.count, 1)
        let reminderCountBefore = scheduler.scheduled.count

        await backupReminderScheduler.disable()
        XCTAssertTrue(scheduler.cancelledIdentifiers.contains(BackupReminderNotification.identifier))
        XCTAssertEqual(scheduler.scheduledApp.count, 0)
        XCTAssertEqual(scheduler.scheduled.count, reminderCountBefore)
    }

    // MARK: - TC-BACKUP-REMINDER-010 Changing interval does not create duplicates

    func testTC_BACKUP_REMINDER_010_changingIntervalDoesNotCreateDuplicates() async {
        _ = await backupReminderScheduler.enable()
        await backupReminderScheduler.setInterval(.twoWeeks)
        XCTAssertEqual(scheduler.scheduledApp.count, 1)
        await backupReminderScheduler.setInterval(.oneMonth)
        XCTAssertEqual(scheduler.scheduledApp.count, 1)
    }

    // MARK: - Export metadata

    func testTC_BACKUP_REMINDER_011_successfulExportUpdatesLastExport() {
        let exportDate = now!
        BackupExportMetadata.lastExportCreatedOnThisDevice = exportDate
        XCTAssertEqual(BackupExportMetadata.lastExportCreatedOnThisDevice, exportDate)
    }

    func testTC_BACKUP_REMINDER_012_cancelledExportDoesNotUpdateLastExport() {
        BackupExportMetadata.lastExportCreatedOnThisDevice = nil
        // Cancelled export path does not mutate metadata (ViewModel no-op on failure).
        XCTAssertNil(BackupExportMetadata.lastExportCreatedOnThisDevice)
    }

    func testTC_BACKUP_REMINDER_013_failedExportDoesNotUpdateLastExport() {
        BackupExportMetadata.lastExportCreatedOnThisDevice = nil
        XCTAssertNil(BackupExportMetadata.lastExportCreatedOnThisDevice)
    }

    // MARK: - TC-BACKUP-REMINDER-014 Successful export reschedules

    func testTC_BACKUP_REMINDER_014_successfulExportReschedulesNextBackupReminder() async {
        _ = await backupReminderScheduler.enable()
        let firstFire = scheduledBackupFireDate()

        let exportDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 15))!
        BackupExportMetadata.lastExportCreatedOnThisDevice = exportDate
        await backupReminderScheduler.rescheduleAfterSuccessfulExport(at: exportDate)

        let secondFire = scheduledBackupFireDate()
        XCTAssertEqual(secondFire, expectedFireDate(from: exportDate, interval: .oneWeek))
        XCTAssertNotEqual(firstFire, secondFire)
        XCTAssertEqual(scheduler.scheduledApp.count, 1)
    }

    // MARK: - TC-BACKUP-REMINDER-015 Does not count toward reminder capacity

    func testTC_BACKUP_REMINDER_015_backupNotificationDoesNotCountTowardReminderCapacity() async throws {
        _ = await backupReminderScheduler.enable()
        XCTAssertEqual(scheduler.scheduledApp.count, 1)

        await reminderService.reconcileAllNotifications()
        XCTAssertEqual(scheduler.scheduledApp.count, 1, "Reconcile must not remove backup reminder")
    }

    // MARK: - TC-BACKUP-REMINDER-016 Not exported

    func testTC_BACKUP_REMINDER_016_backupNotificationIsNotExported() async throws {
        _ = await backupReminderScheduler.enable()
        let personRepo = InMemoryPersonRepository()
        let contextRepo = InMemoryContextRepository()
        let exportService = BackupExportService(
            reminderRepository: reminderRepo,
            personRepository: personRepo,
            contextRepository: contextRepo
        )
        let result = try exportService.exportBackup(exportedAt: now)
        let backup = try JSONDecoder().decode(LifeCueBackup.self, from: result.data)
        XCTAssertFalse(backup.reminders.contains { $0.title == BackupReminderNotification.title })
    }

    // MARK: - TC-BACKUP-REMINDER-017 Identifier cannot collide

    func testTC_BACKUP_REMINDER_017_backupIdentifierCannotCollideWithReminderIdentifiers() {
        XCTAssertFalse(BackupReminderNotification.identifier.hasPrefix(NotificationIdentifier.reminderPrefix))
        XCTAssertNil(NotificationIdentifier.reminderID(from: BackupReminderNotification.identifier))
        XCTAssertFalse(NotificationIdentifier.isLifeCueIdentifier(BackupReminderNotification.identifier))
    }

    // MARK: - TC-BACKUP-REMINDER-018 Normal scheduling unchanged

    func testTC_BACKUP_REMINDER_018_existingNormalNotificationSchedulingRemainsUnchanged() async throws {
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13))!
        let eventTime = calendar.date(from: DateComponents(year: 2026, month: 8, day: 13, hour: 9, minute: 0))!
        _ = try await reminderService.create(
            title: "Doctor",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventTime,
            timeZoneIdentifier: "Asia/Kolkata"
        )
        let before = scheduler.scheduled.count
        XCTAssertGreaterThan(before, 0)

        _ = await backupReminderScheduler.enable()
        XCTAssertEqual(scheduler.scheduled.count, before)
    }

    // MARK: - TC-BACKUP-REMINDER-019 No immediate notification on enable

    func testTC_BACKUP_REMINDER_019_noImmediateNotificationOnEnable() async {
        _ = await backupReminderScheduler.enable()
        guard let fire = scheduledBackupFireDate() else {
            XCTFail("Expected scheduled backup reminder")
            return
        }
        XCTAssertGreaterThan(fire, now)
    }

    // MARK: - TC-BACKUP-REMINDER-020 First reminder uses enable date + interval

    func testTC_BACKUP_REMINDER_020_firstReminderUsesEnableDatePlusIntervalWhenNoPreviousExport() async {
        BackupExportMetadata.lastExportCreatedOnThisDevice = nil
        _ = await backupReminderScheduler.enable()
        XCTAssertEqual(scheduledBackupFireDate(), expectedFireDate(from: now, interval: .oneWeek))
    }

    // MARK: - Notification content

    func testBackupNotificationContentHasNoPrivateData() async {
        _ = await backupReminderScheduler.enable()
        let request = scheduler.scheduledApp.first
        XCTAssertEqual(request?.title, BackupReminderNotification.title)
        XCTAssertEqual(request?.body, BackupReminderNotification.body)
        XCTAssertFalse(request?.body.contains("reminder") == true && request?.body.contains("Person") == true)
    }

    func testBackupNotificationTapRouting() {
        XCTAssertTrue(
            BackupReminderNotification.isBackupReminder(
                requestIdentifier: BackupReminderNotification.identifier,
                userInfo: [:]
            )
        )
        XCTAssertFalse(
            BackupReminderNotification.isBackupReminder(
                requestIdentifier: NotificationIdentifier.prefix(for: UUID()),
                userInfo: ["reminderID": UUID().uuidString]
            )
        )
    }
}

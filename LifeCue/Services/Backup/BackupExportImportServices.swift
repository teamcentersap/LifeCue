import Foundation

@MainActor
protocol BackupExportServing: AnyObject {
    func exportBackup(exportedAt: Date) throws -> (backup: LifeCueBackup, data: Data, counts: BackupInventoryCounts)
}

@MainActor
final class BackupExportService: BackupExportServing {
    private let reminderRepository: ReminderRepository
    private let personRepository: PersonRepository
    private let contextRepository: ContextRepository

    init(
        reminderRepository: ReminderRepository,
        personRepository: PersonRepository,
        contextRepository: ContextRepository
    ) {
        self.reminderRepository = reminderRepository
        self.personRepository = personRepository
        self.contextRepository = contextRepository
    }

    func exportBackup(exportedAt: Date = Date()) throws -> (backup: LifeCueBackup, data: Data, counts: BackupInventoryCounts) {
        let reminders = try reminderRepository.fetchAll()
        let people = try personRepository.fetchAll()
        let contexts = try contextRepository.fetchAll()

        let backup = LifeCueBackupMapper.makeBackup(
            people: people,
            contexts: contexts,
            reminders: reminders,
            exportedAt: exportedAt
        )
        try BackupValidator.validateExport(backup)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(backup)
        } catch {
            throw BackupValidationError.unreadable
        }
        let counts = BackupInventoryCounts(
            reminders: reminders.count,
            people: people.count,
            contexts: contexts.count
        )
        return (backup, data, counts)
    }
}

struct BackupImportPreview: Equatable, Sendable {
    var backup: LifeCueBackup
    var snapshot: BackupDomainSnapshot
    var backupCounts: BackupInventoryCounts
    var currentCounts: BackupInventoryCounts
    var exportedAt: Date?
}

@MainActor
protocol BackupImportServing: AnyObject {
    func prepareImport(from data: Data) throws -> BackupImportPreview
    func replace(with preview: BackupImportPreview) async throws -> NotificationReconcileResult
}

@MainActor
final class BackupImportService: BackupImportServing {
    private let store: BackupStoreReplacing
    private let reminderService: ReminderService

    init(store: BackupStoreReplacing, reminderService: ReminderService) {
        self.store = store
        self.reminderService = reminderService
    }

    /// Validates fully. Does not mutate persistence.
    func prepareImport(from data: Data) throws -> BackupImportPreview {
        let (backup, snapshot) = try BackupValidator.decodeAndValidate(data: data)
        let current = try store.currentCounts()
        return BackupImportPreview(
            backup: backup,
            snapshot: snapshot,
            backupCounts: BackupInventoryCounts(
                reminders: snapshot.reminderCount,
                people: snapshot.personCount,
                contexts: snapshot.contextCount
            ),
            currentCounts: current,
            exportedAt: BackupJSONDate.decode(backup.exportedAt)
        )
    }

    /// Explicit Replace only. Requires a previously validated preview.
    func replace(with preview: BackupImportPreview) async throws -> NotificationReconcileResult {
        // Re-validate snapshot integrity immediately before mutation.
        try BackupValidator.validateDomainSnapshot(preview.snapshot)
        try store.replaceAll(with: preview.snapshot)
        // Rebuild notifications through existing ReminderService path only.
        return await reminderService.reconcileAllNotifications()
    }
}

enum BackupFileNaming {
    static func suggestedFileName(for date: Date, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 1970
        let m = comps.month ?? 1
        let d = comps.day ?? 1
        let month = String(format: "%02d", m)
        let day = String(format: "%02d", d)
        return "LifeCue Backup \(y)-\(month)-\(day).lifecuebackup"
    }
}

enum BackupExportMetadata {
    private static let lastExportKey = "lifecue.lastExportCreatedOnThisDevice"

    static var lastExportCreatedOnThisDevice: Date? {
        get { UserDefaults.standard.object(forKey: lastExportKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastExportKey) }
    }
}

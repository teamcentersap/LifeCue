import Foundation
import SwiftData

/// Atomic replacement of all LifeCue domain entities.
///
/// SwiftData strategy: stage deletes + inserts with autosave disabled, then a single
/// `ModelContext.save()`. On failure, `rollback()` leaves the store unchanged.
@MainActor
protocol BackupStoreReplacing: AnyObject {
    func currentCounts() throws -> BackupInventoryCounts
    func replaceAll(with snapshot: BackupDomainSnapshot) throws
}

enum BackupStoreError: Error, Equatable {
    case replaceFailed
}

/// Production replacer using one shared `ModelContext`.
@MainActor
final class SwiftDataBackupStoreReplacer: BackupStoreReplacing {
    private let modelContext: ModelContext

    /// Test seam: invoked immediately before `save()`. Throw to simulate persistence failure.
    var testWillSave: (() throws -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func currentCounts() throws -> BackupInventoryCounts {
        BackupInventoryCounts(
            reminders: try modelContext.fetchCount(FetchDescriptor<ReminderRecord>()),
            people: try modelContext.fetchCount(FetchDescriptor<PersonRecord>()),
            contexts: try modelContext.fetchCount(FetchDescriptor<ContextRecord>())
        )
    }

    func replaceAll(with snapshot: BackupDomainSnapshot) throws {
        // Pre-materialize records so encoding failures happen before any mutation.
        let personRecords = snapshot.people.map(PersonRecord.init(from:))
        let contextRecords = snapshot.contexts.map(ContextRecord.init(from:))
        let reminderRecords: [ReminderRecord]
        do {
            reminderRecords = try snapshot.reminders.map { try ReminderRecord(from: $0) }
        } catch {
            throw BackupValidationError.replaceFailed
        }

        let previousAutosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = previousAutosave }

        do {
            if modelContext.hasChanges {
                modelContext.rollback()
            }

            try deleteAll(ReminderRecord.self)
            try deleteAll(PersonRecord.self)
            try deleteAll(ContextRecord.self)

            for record in personRecords {
                modelContext.insert(record)
            }
            for record in contextRecords {
                modelContext.insert(record)
            }
            for record in reminderRecords {
                modelContext.insert(record)
            }

            try testWillSave?()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw BackupValidationError.replaceFailed
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) throws {
        let existing = try modelContext.fetch(FetchDescriptor<T>())
        for record in existing {
            modelContext.delete(record)
        }
    }
}

/// Test doubles: dictionary swap is atomic in-process.
@MainActor
final class InMemoryBackupStoreReplacer: BackupStoreReplacing {
    private let reminderRepository: InMemoryReminderRepository
    private let personRepository: InMemoryPersonRepository
    private let contextRepository: InMemoryContextRepository

    /// Optional hook to simulate persistence failure after validation.
    var shouldFailReplace = false

    init(
        reminderRepository: InMemoryReminderRepository,
        personRepository: InMemoryPersonRepository,
        contextRepository: InMemoryContextRepository
    ) {
        self.reminderRepository = reminderRepository
        self.personRepository = personRepository
        self.contextRepository = contextRepository
    }

    func currentCounts() throws -> BackupInventoryCounts {
        BackupInventoryCounts(
            reminders: try reminderRepository.fetchAll().count,
            people: try personRepository.fetchAll().count,
            contexts: try contextRepository.fetchAll().count
        )
    }

    func replaceAll(with snapshot: BackupDomainSnapshot) throws {
        if shouldFailReplace {
            throw BackupValidationError.replaceFailed
        }

        // Build complete replacement maps first; only then swap (no partial visible state).
        var people: [UUID: Person] = [:]
        for person in snapshot.people {
            people[person.id] = person
        }
        var contexts: [UUID: ReminderContext] = [:]
        for context in snapshot.contexts {
            contexts[context.id] = context
        }
        var reminders: [UUID: Reminder] = [:]
        for reminder in snapshot.reminders {
            reminders[reminder.id] = reminder
        }

        personRepository.replaceStorage(people)
        contextRepository.replaceStorage(contexts)
        reminderRepository.replaceStorage(reminders)
    }
}

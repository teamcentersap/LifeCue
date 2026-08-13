import Foundation

/// In-memory repository for domain tests and previews.
@MainActor
final class InMemoryReminderRepository: ReminderRepository {
    private var storage: [UUID: Reminder] = [:]

    init(reminders: [Reminder] = []) {
        for reminder in reminders {
            storage[reminder.id] = reminder
        }
    }

    func fetchAllOutcome() throws -> ReminderFetchOutcome {
        let reminders = try fetchAll()
        return ReminderFetchOutcome(reminders: reminders, skippedCorruptRecordIDs: [])
    }

    func fetchAll() throws -> [Reminder] {
        Array(storage.values).sorted { lhs, rhs in
            let left = lhs.sortDate() ?? .distantFuture
            let right = rhs.sortDate() ?? .distantFuture
            return left < right
        }
    }

    func fetch(id: UUID) throws -> Reminder? {
        storage[id]
    }

    func save(_ reminder: Reminder) throws {
        storage[reminder.id] = reminder
    }

    func delete(id: UUID) throws {
        storage.removeValue(forKey: id)
    }

    /// Atomic full replace used by backup restore tests.
    func replaceStorage(_ newStorage: [UUID: Reminder]) {
        storage = newStorage
    }
}

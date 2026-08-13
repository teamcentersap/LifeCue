import Foundation

/// Persistence boundary for reminders. Keeps SwiftUI free of storage details.
@MainActor
protocol ReminderRepository: AnyObject {
    func fetchAllOutcome() throws -> ReminderFetchOutcome
    func fetch(id: UUID) throws -> Reminder?
    func save(_ reminder: Reminder) throws
    func delete(id: UUID) throws
}

extension ReminderRepository {
    func fetchAll() throws -> [Reminder] {
        try fetchAllOutcome().reminders
    }
}

enum ReminderRepositoryError: Error, Equatable {
    case notFound
    case persistenceFailed(String)
}

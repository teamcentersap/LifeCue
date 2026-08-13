import Foundation
import SwiftData

@MainActor
final class SwiftDataReminderRepository: ReminderRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAllOutcome() throws -> ReminderFetchOutcome {
        let descriptor = FetchDescriptor<ReminderRecord>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        let records = try modelContext.fetch(descriptor)
        var reminders: [Reminder] = []
        var skipped: [UUID] = []
        for record in records {
            do {
                reminders.append(try record.asDomain())
            } catch {
                skipped.append(record.id)
            }
        }
        return ReminderFetchOutcome(reminders: reminders, skippedCorruptRecordIDs: skipped)
    }

    func fetch(id: UUID) throws -> Reminder? {
        let descriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let record = try modelContext.fetch(descriptor).first else { return nil }
        return try record.asDomain()
    }

    func save(_ reminder: Reminder) throws {
        let targetID = reminder.id
        let descriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            try existing.apply(reminder)
        } else {
            modelContext.insert(try ReminderRecord(from: reminder))
        }
        try modelContext.save()
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<ReminderRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let existing = try modelContext.fetch(descriptor).first else {
            throw ReminderRepositoryError.notFound
        }
        modelContext.delete(existing)
        try modelContext.save()
    }
}

enum LifeCuePersistence {
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            isStoredInMemoryOnly: inMemory
        )
        // Optional personID/contextID on ReminderRecord + new Person/Context models.
        // SwiftData lightweight migration accepts new optional attributes / new models.
        return try ModelContainer(
            for: ReminderRecord.self, PersonRecord.self, ContextRecord.self,
            configurations: configuration
        )
    }
}

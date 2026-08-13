import Foundation
import SwiftData

@MainActor
protocol ContextRepository: AnyObject {
    func fetchAll() throws -> [ReminderContext]
    func fetch(id: UUID) throws -> ReminderContext?
    func save(_ context: ReminderContext) throws
    func delete(id: UUID) throws
}

@MainActor
final class InMemoryContextRepository: ContextRepository {
    private var storage: [UUID: ReminderContext] = [:]

    func fetchAll() throws -> [ReminderContext] {
        storage.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetch(id: UUID) throws -> ReminderContext? {
        storage[id]
    }

    func save(_ context: ReminderContext) throws {
        storage[context.id] = context
    }

    func delete(id: UUID) throws {
        guard storage.removeValue(forKey: id) != nil else {
            throw ContextValidationError.notFound
        }
    }

    /// Atomic full replace used by backup restore tests.
    func replaceStorage(_ newStorage: [UUID: ReminderContext]) {
        storage = newStorage
    }
}

@MainActor
final class SwiftDataContextRepository: ContextRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [ReminderContext] {
        let descriptor = FetchDescriptor<ContextRecord>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { $0.asDomain() }
    }

    func fetch(id: UUID) throws -> ReminderContext? {
        let descriptor = FetchDescriptor<ContextRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first?.asDomain()
    }

    func save(_ context: ReminderContext) throws {
        let targetID = context.id
        let descriptor = FetchDescriptor<ContextRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(context)
        } else {
            modelContext.insert(ContextRecord(from: context))
        }
        try modelContext.save()
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<ContextRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let existing = try modelContext.fetch(descriptor).first else {
            throw ContextValidationError.notFound
        }
        modelContext.delete(existing)
        try modelContext.save()
    }
}

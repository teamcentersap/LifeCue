import Foundation
import SwiftData

@MainActor
protocol PersonRepository: AnyObject {
    func fetchAll() throws -> [Person]
    func fetch(id: UUID) throws -> Person?
    func save(_ person: Person) throws
    func delete(id: UUID) throws
}

@MainActor
final class InMemoryPersonRepository: PersonRepository {
    private var storage: [UUID: Person] = [:]

    func fetchAll() throws -> [Person] {
        storage.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetch(id: UUID) throws -> Person? {
        storage[id]
    }

    func save(_ person: Person) throws {
        storage[person.id] = person
    }

    func delete(id: UUID) throws {
        guard storage.removeValue(forKey: id) != nil else {
            throw PersonValidationError.notFound
        }
    }

    /// Atomic full replace used by backup restore tests.
    func replaceStorage(_ newStorage: [UUID: Person]) {
        storage = newStorage
    }
}

@MainActor
final class SwiftDataPersonRepository: PersonRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func fetchAll() throws -> [Person] {
        let descriptor = FetchDescriptor<PersonRecord>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        return try modelContext.fetch(descriptor).map { $0.asDomain() }
    }

    func fetch(id: UUID) throws -> Person? {
        let descriptor = FetchDescriptor<PersonRecord>(
            predicate: #Predicate { $0.id == id }
        )
        return try modelContext.fetch(descriptor).first?.asDomain()
    }

    func save(_ person: Person) throws {
        let targetID = person.id
        let descriptor = FetchDescriptor<PersonRecord>(
            predicate: #Predicate { $0.id == targetID }
        )
        if let existing = try modelContext.fetch(descriptor).first {
            existing.apply(person)
        } else {
            modelContext.insert(PersonRecord(from: person))
        }
        try modelContext.save()
    }

    func delete(id: UUID) throws {
        let descriptor = FetchDescriptor<PersonRecord>(
            predicate: #Predicate { $0.id == id }
        )
        guard let existing = try modelContext.fetch(descriptor).first else {
            throw PersonValidationError.notFound
        }
        modelContext.delete(existing)
        try modelContext.save()
    }
}

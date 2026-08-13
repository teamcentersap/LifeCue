import Foundation

/// CRUD for optional People. Prefer archive for historical reminder references;
/// permanent deletion is coordinated by `OrganizationDeletionService`.
@MainActor
final class PersonService {
    private let repository: PersonRepository
    private var clock: () -> Date

    init(repository: PersonRepository, clock: @escaping () -> Date = { Date() }) {
        self.repository = repository
        self.clock = clock
    }

    func allPeople(includeArchived: Bool = false) throws -> [Person] {
        let people = try repository.fetchAll()
        if includeArchived { return people }
        return people.filter(\.isActive)
    }

    func person(id: UUID) throws -> Person? {
        try repository.fetch(id: id)
    }

    @discardableResult
    func create(
        name: String,
        relationship: String? = nil,
        iconName: String? = nil,
        colorToken: String? = nil
    ) throws -> Person {
        guard let normalized = Person.normalizedName(name) else {
            throw PersonValidationError.emptyName
        }
        let now = clock()
        let person = Person(
            name: normalized,
            relationship: relationship,
            iconName: iconName,
            colorToken: colorToken,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
        try repository.save(person)
        return person
    }

    @discardableResult
    func update(_ person: Person) throws -> Person {
        guard try repository.fetch(id: person.id) != nil else {
            throw PersonValidationError.notFound
        }
        guard let normalized = Person.normalizedName(person.name) else {
            throw PersonValidationError.emptyName
        }
        var updated = person
        updated.name = normalized
        updated.relationship = Person.normalizedOptional(person.relationship)
        updated.iconName = Person.normalizedOptional(person.iconName)
        updated.colorToken = Person.normalizedOptional(person.colorToken)
        updated.updatedAt = clock()
        try repository.save(updated)
        return updated
    }

    @discardableResult
    func archive(id: UUID) throws -> Person {
        guard var person = try repository.fetch(id: id) else {
            throw PersonValidationError.notFound
        }
        person.isArchived = true
        person.updatedAt = clock()
        try repository.save(person)
        return person
    }

    /// Restores an archived Person to Active. Does not cascade to Contexts or Reminders.
    @discardableResult
    func unarchive(id: UUID) throws -> Person {
        guard var person = try repository.fetch(id: id) else {
            throw PersonValidationError.notFound
        }
        person.isArchived = false
        person.updatedAt = clock()
        try repository.save(person)
        return person
    }
}

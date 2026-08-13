import Foundation

/// CRUD for optional Contexts. Prefer archive for historical reminder references;
/// permanent deletion is coordinated by `OrganizationDeletionService`.
@MainActor
final class ContextService {
    private let repository: ContextRepository
    private let personRepository: PersonRepository
    private var clock: () -> Date

    init(
        repository: ContextRepository,
        personRepository: PersonRepository,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.personRepository = personRepository
        self.clock = clock
    }

    func allContexts(includeArchived: Bool = false) throws -> [ReminderContext] {
        let contexts = try repository.fetchAll()
        if includeArchived { return contexts }
        return contexts.filter(\.isActive)
    }

    func contexts(forPersonID personID: UUID?, includeGlobal: Bool = true) throws -> [ReminderContext] {
        let active = try allContexts(includeArchived: false)
        return active.filter { context in
            if let personID {
                if context.personID == personID { return true }
                if includeGlobal && context.isGlobal { return true }
                return false
            }
            return context.isGlobal
        }
    }

    func context(id: UUID) throws -> ReminderContext? {
        try repository.fetch(id: id)
    }

    @discardableResult
    func create(
        name: String,
        personID: UUID? = nil,
        iconName: String? = nil,
        colorToken: String? = nil
    ) throws -> ReminderContext {
        guard let normalized = Person.normalizedName(name) else {
            throw ContextValidationError.emptyName
        }
        if let personID {
            guard let person = try personRepository.fetch(id: personID), person.isActive else {
                throw ContextValidationError.invalidPerson
            }
        }
        let now = clock()
        let context = ReminderContext(
            name: normalized,
            iconName: iconName,
            colorToken: colorToken,
            personID: personID,
            isArchived: false,
            createdAt: now,
            updatedAt: now
        )
        try repository.save(context)
        return context
    }

    @discardableResult
    func update(_ context: ReminderContext) throws -> ReminderContext {
        guard try repository.fetch(id: context.id) != nil else {
            throw ContextValidationError.notFound
        }
        guard let normalized = Person.normalizedName(context.name) else {
            throw ContextValidationError.emptyName
        }
        if let personID = context.personID {
            guard let person = try personRepository.fetch(id: personID) else {
                throw ContextValidationError.invalidPerson
            }
            // New assignment must be active; already-linked archived person may remain on edit.
            if !person.isActive {
                let existing = try repository.fetch(id: context.id)
                if existing?.personID != personID {
                    throw ContextValidationError.invalidPerson
                }
            }
        }
        var updated = context
        updated.name = normalized
        updated.iconName = Person.normalizedOptional(context.iconName)
        updated.colorToken = Person.normalizedOptional(context.colorToken)
        updated.updatedAt = clock()
        try repository.save(updated)
        return updated
    }

    @discardableResult
    func archive(id: UUID) throws -> ReminderContext {
        guard var context = try repository.fetch(id: id) else {
            throw ContextValidationError.notFound
        }
        context.isArchived = true
        context.updatedAt = clock()
        try repository.save(context)
        return context
    }

    /// Restores an archived Context to Active. Does not cascade to its Person or Reminders.
    @discardableResult
    func unarchive(id: UUID) throws -> ReminderContext {
        guard var context = try repository.fetch(id: id) else {
            throw ContextValidationError.notFound
        }
        context.isArchived = false
        context.updatedAt = clock()
        try repository.save(context)
        return context
    }
}

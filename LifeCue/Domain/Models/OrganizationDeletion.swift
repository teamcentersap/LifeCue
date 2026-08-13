import Foundation
import SwiftData

/// Counts used by Delete Person confirmation UI.
struct PersonDeletionDependencies: Equatable, Sendable {
    var reminderCount: Int
    var personalContextCount: Int

    var isEmpty: Bool { reminderCount == 0 && personalContextCount == 0 }
}

/// Counts used by Delete Context confirmation UI.
struct ContextDeletionDependencies: Equatable, Sendable {
    var reminderCount: Int

    var isEmpty: Bool { reminderCount == 0 }
}

enum OrganizationDeletionPresentation {
    static func personUnusedTitle() -> String { "Delete Person?" }

    static func personUnusedMessage() -> String {
        "This person isn't used by any reminders or personal contexts. The person will be permanently deleted."
    }

    static func personUsedTitle() -> String { "Delete Person?" }

    static func personUsedMessage(dependencies: PersonDeletionDependencies) -> String {
        let reminders = dependencies.reminderCount
        let contexts = dependencies.personalContextCount
        let reminderWord = reminders == 1 ? "reminder" : "reminders"
        let contextWord = contexts == 1 ? "personal context" : "personal contexts"
        return """
        This person is used by \(reminders) \(reminderWord) and has \(contexts) \(contextWord). \
        Deleting this person will permanently delete the person, \(reminders) \(reminderWord), and \(contexts) \(contextWord). \
        This action cannot be undone.
        """
    }

    static func personDeleteActionTitle(dependencies: PersonDeletionDependencies) -> String {
        dependencies.isEmpty ? "Delete Person" : "Delete Person & Data"
    }

    static func contextUnusedTitle() -> String { "Delete Context?" }

    static func contextUnusedMessage() -> String {
        "This context isn't used by any reminders. The context will be permanently deleted."
    }

    static func contextUsedTitle() -> String { "Context Is Used by Reminders" }

    static func contextUsedMessage(dependencies: ContextDeletionDependencies) -> String {
        let count = dependencies.reminderCount
        let word = count == 1 ? "reminder" : "reminders"
        return """
        This context is associated with \(count) \(word). \
        You can archive the context to keep those reminders, or permanently delete the context and those reminders.
        """
    }

    static func contextDeleteActionTitle(dependencies: ContextDeletionDependencies) -> String {
        if dependencies.isEmpty { return "Delete Context" }
        let count = dependencies.reminderCount
        let word = count == 1 ? "Reminder" : "Reminders"
        return "Delete \(count) \(word) & Context"
    }
}

enum OrganizationDeletionError: Error, Equatable, LocalizedError {
    case notFound
    case cascadeFailed
    case reminderDeletionFailed

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "That item is no longer available."
        case .cascadeFailed:
            return "Couldn't finish deleting. Your data was left unchanged where possible."
        case .reminderDeletionFailed:
            return "Couldn't delete one or more reminders. The person/context was not deleted."
        }
    }
}

/// Atomically removes personal contexts then the person (no orphan `context.personID`).
@MainActor
protocol PersonCascadeDeleting: AnyObject {
    func deletePersonalContextsThenPerson(personID: UUID, personalContextIDs: [UUID]) throws
}

/// In-memory all-or-nothing cascade for tests.
@MainActor
final class InMemoryPersonCascadeDeleter: PersonCascadeDeleting {
    private let personRepository: InMemoryPersonRepository
    private let contextRepository: InMemoryContextRepository
    /// Test seam: throw before applying mutation.
    var testWillCommit: (() throws -> Void)?

    init(
        personRepository: InMemoryPersonRepository,
        contextRepository: InMemoryContextRepository
    ) {
        self.personRepository = personRepository
        self.contextRepository = contextRepository
    }

    func deletePersonalContextsThenPerson(personID: UUID, personalContextIDs: [UUID]) throws {
        let peopleSnapshot = Dictionary(
            uniqueKeysWithValues: (try personRepository.fetchAll()).map { ($0.id, $0) }
        )
        let contextsSnapshot = Dictionary(
            uniqueKeysWithValues: (try contextRepository.fetchAll()).map { ($0.id, $0) }
        )
        do {
            try testWillCommit?()
            for contextID in personalContextIDs {
                try contextRepository.delete(id: contextID)
            }
            try personRepository.delete(id: personID)
        } catch {
            personRepository.replaceStorage(peopleSnapshot)
            contextRepository.replaceStorage(contextsSnapshot)
            throw OrganizationDeletionError.cascadeFailed
        }
    }
}

/// SwiftData cascade using one `ModelContext.save()` with rollback on failure.
@MainActor
final class SwiftDataPersonCascadeDeleter: PersonCascadeDeleting {
    private let modelContext: ModelContext
    /// Test seam: invoked immediately before `save()`.
    var testWillSave: (() throws -> Void)?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func deletePersonalContextsThenPerson(personID: UUID, personalContextIDs: [UUID]) throws {
        let previousAutosave = modelContext.autosaveEnabled
        modelContext.autosaveEnabled = false
        defer { modelContext.autosaveEnabled = previousAutosave }

        do {
            if modelContext.hasChanges {
                modelContext.rollback()
            }

            for contextID in personalContextIDs {
                let descriptor = FetchDescriptor<ContextRecord>(
                    predicate: #Predicate { $0.id == contextID }
                )
                if let record = try modelContext.fetch(descriptor).first {
                    modelContext.delete(record)
                }
            }

            let personDescriptor = FetchDescriptor<PersonRecord>(
                predicate: #Predicate { $0.id == personID }
            )
            guard let personRecord = try modelContext.fetch(personDescriptor).first else {
                throw OrganizationDeletionError.notFound
            }
            modelContext.delete(personRecord)

            try testWillSave?()
            try modelContext.save()
        } catch let error as OrganizationDeletionError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw OrganizationDeletionError.cascadeFailed
        }
    }
}

/// Coordinates permanent Person/Context deletion with ReminderService notification cleanup.
@MainActor
final class OrganizationDeletionService {
    private let personRepository: PersonRepository
    private let contextRepository: ContextRepository
    private let reminderService: ReminderService
    private let personCascade: PersonCascadeDeleting

    init(
        personRepository: PersonRepository,
        contextRepository: ContextRepository,
        reminderService: ReminderService,
        personCascade: PersonCascadeDeleting
    ) {
        self.personRepository = personRepository
        self.contextRepository = contextRepository
        self.reminderService = reminderService
        self.personCascade = personCascade
    }

    func personDependencies(personID: UUID) throws -> PersonDeletionDependencies {
        guard try personRepository.fetch(id: personID) != nil else {
            throw OrganizationDeletionError.notFound
        }
        let personalContextIDs = try personalContextIDs(for: personID)
        let reminders = try remindersAffectedByPersonDeletion(
            personID: personID,
            personalContextIDs: personalContextIDs
        )
        return PersonDeletionDependencies(
            reminderCount: reminders.count,
            personalContextCount: personalContextIDs.count
        )
    }

    func contextDependencies(contextID: UUID) throws -> ContextDeletionDependencies {
        guard try contextRepository.fetch(id: contextID) != nil else {
            throw OrganizationDeletionError.notFound
        }
        let count = try reminderService.allReminders().filter { $0.contextID == contextID }.count
        return ContextDeletionDependencies(reminderCount: count)
    }

    /// Permanently deletes a Person, referencing reminders, and person-specific Contexts.
    func permanentlyDeletePerson(id personID: UUID) async throws {
        guard try personRepository.fetch(id: personID) != nil else {
            throw OrganizationDeletionError.notFound
        }
        let personalContextIDs = try personalContextIDs(for: personID)
        let reminders = try remindersAffectedByPersonDeletion(
            personID: personID,
            personalContextIDs: personalContextIDs
        )

        // ReminderService.delete cancels notifications before removing each reminder.
        // Stop before cascading Person/Contexts if any reminder deletion fails (no orphans).
        do {
            for reminder in reminders {
                try await reminderService.delete(id: reminder.id)
            }
        } catch {
            throw OrganizationDeletionError.reminderDeletionFailed
        }

        try personCascade.deletePersonalContextsThenPerson(
            personID: personID,
            personalContextIDs: personalContextIDs
        )
    }

    /// Permanently deletes a Context and any reminders that reference it. Never deletes a Person.
    func permanentlyDeleteContext(id contextID: UUID) async throws {
        guard try contextRepository.fetch(id: contextID) != nil else {
            throw OrganizationDeletionError.notFound
        }
        let reminders = try reminderService.allReminders().filter { $0.contextID == contextID }

        do {
            for reminder in reminders {
                try await reminderService.delete(id: reminder.id)
            }
        } catch {
            throw OrganizationDeletionError.reminderDeletionFailed
        }

        do {
            try contextRepository.delete(id: contextID)
        } catch {
            throw OrganizationDeletionError.cascadeFailed
        }
    }

    private func personalContextIDs(for personID: UUID) throws -> [UUID] {
        try contextRepository.fetchAll()
            .filter { $0.personID == personID }
            .map(\.id)
    }

    /// Reminders owned by the person, plus any that still point at that person's personal contexts.
    private func remindersAffectedByPersonDeletion(
        personID: UUID,
        personalContextIDs: [UUID]
    ) throws -> [Reminder] {
        let contextIDSet = Set(personalContextIDs)
        return try reminderService.allReminders().filter { reminder in
            if reminder.personID == personID { return true }
            if let contextID = reminder.contextID, contextIDSet.contains(contextID) {
                return true
            }
            return false
        }
    }
}

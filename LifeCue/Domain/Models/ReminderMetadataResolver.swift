import Foundation

/// Resolves optional Person/Context labels for display without embedding names in Reminder.
@MainActor
struct ReminderMetadataResolver {
    let personService: PersonService
    let contextService: ContextService

    func personName(for reminder: Reminder) -> String? {
        guard let id = reminder.personID,
              let person = try? personService.person(id: id) else { return nil }
        return person.isArchived ? "\(person.name) (archived)" : person.name
    }

    func contextName(for reminder: Reminder) -> String? {
        guard let id = reminder.contextID,
              let context = try? contextService.context(id: id) else { return nil }
        return context.isArchived ? "\(context.name) (archived)" : context.name
    }

    func compactSubtitle(for reminder: Reminder) -> String? {
        let parts = [personName(for: reminder), contextName(for: reminder)].compactMap { $0 }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
}

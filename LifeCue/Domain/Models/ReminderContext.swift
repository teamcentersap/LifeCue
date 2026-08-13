import Foundation

/// Optional organizational label for reminders ("Doctor", "School", …).
///
/// Named `ReminderContext` because `Context` collides with system types.
/// A context may be global (`personID == nil`) or person-specific.
/// Names are **not** globally unique — Child 1 → Doctor and Child 2 → Doctor are distinct.
struct ReminderContext: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var iconName: String?
    var colorToken: String?
    /// When set, this context belongs to that person. Nil = general/global.
    var personID: UUID?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        iconName: String? = nil,
        colorToken: String? = nil,
        personID: UUID? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = Person.normalizedName(name) ?? ""
        self.iconName = Person.normalizedOptional(iconName)
        self.colorToken = Person.normalizedOptional(colorToken)
        self.personID = personID
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isActive: Bool { !isArchived }
    var isGlobal: Bool { personID == nil }
}

enum ContextValidationError: Error, Equatable, LocalizedError {
    case emptyName
    case notFound
    case invalidPerson

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "A name is required."
        case .notFound:
            return "Context not found."
        case .invalidPerson:
            return "That person isn't available."
        }
    }
}

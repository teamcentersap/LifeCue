import Foundation

/// Optional identity used to organize reminders. Local-only; not a family/account entity.
struct Person: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    /// Optional relationship label (e.g. "Daughter"). Never required.
    var relationship: String?
    /// Optional SF Symbol name for simple visual identity.
    var iconName: String?
    /// Optional color token key from the design system (e.g. "today").
    var colorToken: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        relationship: String? = nil,
        iconName: String? = nil,
        colorToken: String? = nil,
        isArchived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = Self.normalizedName(name) ?? ""
        self.relationship = Self.normalizedOptional(relationship)
        self.iconName = Self.normalizedOptional(iconName)
        self.colorToken = Self.normalizedOptional(colorToken)
        self.isArchived = isArchived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var isActive: Bool { !isArchived }

    static func normalizedName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func normalizedOptional(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum PersonValidationError: Error, Equatable, LocalizedError {
    case emptyName
    case notFound

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "A name is required."
        case .notFound:
            return "Person not found."
        }
    }
}

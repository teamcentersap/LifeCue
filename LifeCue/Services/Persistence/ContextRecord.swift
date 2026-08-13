import Foundation
import SwiftData

@Model
final class ContextRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var iconName: String?
    var colorToken: String?
    var personID: UUID?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(from context: ReminderContext) {
        self.id = context.id
        self.name = context.name
        self.iconName = context.iconName
        self.colorToken = context.colorToken
        self.personID = context.personID
        self.isArchived = context.isArchived
        self.createdAt = context.createdAt
        self.updatedAt = context.updatedAt
    }

    func apply(_ context: ReminderContext) {
        name = context.name
        iconName = context.iconName
        colorToken = context.colorToken
        personID = context.personID
        isArchived = context.isArchived
        createdAt = context.createdAt
        updatedAt = context.updatedAt
    }

    func asDomain() -> ReminderContext {
        ReminderContext(
            id: id,
            name: name,
            iconName: iconName,
            colorToken: colorToken,
            personID: personID,
            isArchived: isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

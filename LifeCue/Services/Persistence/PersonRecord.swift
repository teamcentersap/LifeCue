import Foundation
import SwiftData

@Model
final class PersonRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var relationship: String?
    var iconName: String?
    var colorToken: String?
    var isArchived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(from person: Person) {
        self.id = person.id
        self.name = person.name
        self.relationship = person.relationship
        self.iconName = person.iconName
        self.colorToken = person.colorToken
        self.isArchived = person.isArchived
        self.createdAt = person.createdAt
        self.updatedAt = person.updatedAt
    }

    func apply(_ person: Person) {
        name = person.name
        relationship = person.relationship
        iconName = person.iconName
        colorToken = person.colorToken
        isArchived = person.isArchived
        createdAt = person.createdAt
        updatedAt = person.updatedAt
    }

    func asDomain() -> Person {
        Person(
            id: id,
            name: name,
            relationship: relationship,
            iconName: iconName,
            colorToken: colorToken,
            isArchived: isArchived,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

import Foundation

/// Portable LifeCue backup document (data contract). Not a SwiftData dump.
struct LifeCueBackup: Equatable, Sendable, Codable {
    static let formatIdentifier = "LifeCueBackup"
    static let currentSchemaVersion = 1
    static let currentMinimumReaderVersion = 1
    /// Highest schema version this app build can import.
    static let maxSupportedSchemaVersion = 1

    var format: String
    var schemaVersion: Int
    var minimumReaderVersion: Int
    var exportedAt: String
    var people: [LifeCueBackupPerson]
    var contexts: [LifeCueBackupContext]
    var reminders: [LifeCueBackupReminder]

    enum CodingKeys: String, CodingKey {
        case format
        case schemaVersion
        case minimumReaderVersion
        case exportedAt
        case people
        case contexts
        case reminders
    }
}

struct LifeCueBackupPerson: Equatable, Sendable, Codable {
    var id: UUID
    var name: String
    var relationship: String?
    var iconName: String?
    var colorToken: String?
    var isArchived: Bool
    var createdAt: String
    var updatedAt: String
}

struct LifeCueBackupContext: Equatable, Sendable, Codable {
    var id: UUID
    var name: String
    var iconName: String?
    var colorToken: String?
    var personID: UUID?
    var isArchived: Bool
    var createdAt: String
    var updatedAt: String
}

struct LifeCueBackupReminder: Equatable, Sendable, Codable {
    var id: UUID
    var title: String
    var eventDate: LifeCueBackupDateComponents
    var eventTime: LifeCueBackupTimeComponents?
    var timeZoneIdentifier: String
    var note: String?
    var personID: UUID?
    var contextID: UUID?
    var status: String
    var rules: [LifeCueBackupRule]
    var snooze: LifeCueBackupSnooze?
    var createdAt: String
    var updatedAt: String
    var completedAt: String?
}

struct LifeCueBackupDateComponents: Equatable, Sendable, Codable {
    var year: Int
    var month: Int
    var day: Int
}

struct LifeCueBackupTimeComponents: Equatable, Sendable, Codable {
    var hour: Int
    var minute: Int
}

struct LifeCueBackupSnooze: Equatable, Sendable, Codable {
    /// Absolute snooze-until instant as ISO-8601 UTC.
    var until: String
}

struct LifeCueBackupRule: Equatable, Sendable, Codable {
    var id: UUID
    var ruleType: String
    var offsetValue: Int?
    var offsetUnit: String?
    var enabled: Bool
    var recurrence: LifeCueBackupRecurrence?
    var dateWindow: LifeCueBackupDateWindow?
}

struct LifeCueBackupRecurrence: Equatable, Sendable, Codable {
    var frequency: String
    var interval: Int
    var weekdays: [Int]?
    var dayOfMonth: Int?
}

struct LifeCueBackupDateWindow: Equatable, Sendable, Codable {
    var startDate: LifeCueBackupDateComponents
    var endDate: LifeCueBackupDateComponents
}

/// In-memory domain snapshot used after validation / before atomic replace.
struct BackupDomainSnapshot: Equatable, Sendable {
    var people: [Person]
    var contexts: [ReminderContext]
    var reminders: [Reminder]

    var reminderCount: Int { reminders.count }
    var personCount: Int { people.count }
    var contextCount: Int { contexts.count }
}

struct BackupInventoryCounts: Equatable, Sendable {
    var reminders: Int
    var people: Int
    var contexts: Int
}

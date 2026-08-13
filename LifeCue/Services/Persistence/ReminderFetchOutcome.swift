import Foundation

/// Result of loading reminders from persistence, including records that could not be converted.
struct ReminderFetchOutcome: Equatable, Sendable {
    let reminders: [Reminder]
    let skippedCorruptRecordIDs: [UUID]

    var hasSkippedCorruptRecords: Bool {
        !skippedCorruptRecordIDs.isEmpty
    }
}

enum ReminderRecordConversionError: Error, Equatable, Sendable {
    case invalidStatus
    case invalidTimeZone
    case invalidEventDate
}

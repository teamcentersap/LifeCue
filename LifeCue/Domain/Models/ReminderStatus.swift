import Foundation

/// Lifecycle status for a reminder.
enum ReminderStatus: String, Codable, CaseIterable, Sendable {
    case active
    case completed
}

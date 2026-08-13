import Foundation

/// Pure extraction of Reminder ID from a notification response (testable, no UIKit).
enum NotificationTapRouting {
    static let reminderIDUserInfoKey = "reminderID"

    /// Prefer userInfo `reminderID`; fall back to parsing the request identifier.
    static func reminderID(
        requestIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> UUID? {
        if let raw = userInfo[reminderIDUserInfoKey] as? String,
           let id = UUID(uuidString: raw) {
            return id
        }
        return NotificationIdentifier.reminderID(from: requestIdentifier)
    }
}

/// Outcome of resolving a tapped notification against persistence.
enum NotificationTapResolution: Equatable, Sendable {
    /// Open existing ReminderDetailView for this ID (active, completed, or snoozed).
    case open(UUID)
    /// Reminder cannot be resolved — stay on Home / show lightweight message.
    case unavailable
}

enum NotificationTapResolver {
    /// Does not mutate reminders, schedules, snooze, or status.
    static func resolve(
        reminderID: UUID?,
        fetch: (UUID) throws -> Reminder?
    ) -> NotificationTapResolution {
        guard let reminderID else { return .unavailable }
        do {
            guard try fetch(reminderID) != nil else { return .unavailable }
            return .open(reminderID)
        } catch {
            return .unavailable
        }
    }
}

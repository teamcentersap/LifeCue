import Foundation

enum NotificationIdentifier {
    static let reminderPrefix = "lifecue.reminder."

    /// Deterministic ID: reminderID + generation + ruleID + occurrenceKey
    /// Generation scopes IDs so a superseded in-flight add can be cancelled without
    /// deleting notifications belonging to a newer schedule for the same reminder.
    static func occurrence(
        reminderID: UUID,
        generation: UInt64,
        ruleID: UUID,
        occurrenceKey: String
    ) -> String {
        "\(reminderPrefix)\(reminderID.uuidString).g\(generation).occ.\(ruleID.uuidString).\(occurrenceKey)"
    }

    static func snooze(
        reminderID: UUID,
        generation: UInt64,
        occurrenceKey: String
    ) -> String {
        occurrence(
            reminderID: reminderID,
            generation: generation,
            ruleID: ReminderRuleEngine.snoozeRuleNamespace,
            occurrenceKey: occurrenceKey
        )
    }

    static func prefix(for reminderID: UUID) -> String {
        "\(reminderPrefix)\(reminderID.uuidString)."
    }

    static func isLifeCueIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(reminderPrefix)
    }

    static func reminderID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(reminderPrefix) else { return nil }
        let rest = identifier.dropFirst(reminderPrefix.count)
        let uuidPart = rest.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false).first
        guard let uuidPart else { return nil }
        return UUID(uuidString: String(uuidPart))
    }
}

/// App-level notification that is not tied to a Reminder (e.g. Backup Reminder).
struct ScheduledAppNotificationRequest: Equatable, Sendable {
    let identifier: String
    let fireAt: Date
    let title: String
    let body: String
    let userInfo: [String: String]
}

struct ScheduledNotificationRequest: Equatable, Sendable, Identifiable {
    var id: String { identifier }
    let identifier: String
    let fireAt: Date
    let title: String
    let body: String
    let reminderID: UUID
    let ruleID: UUID?
    let occurrenceKey: String?
    let timeZoneIdentifier: String
}

enum NotificationAuthorizationStatus: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unsupported
}

/// Abstraction over UserNotifications so scheduling decisions can be unit-tested.
protocol NotificationScheduling: AnyObject {
    func authorizationStatus() async -> NotificationAuthorizationStatus
    /// Requests permission once when appropriate. Returns the resulting status.
    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationStatus
    func schedule(_ request: ScheduledNotificationRequest) async throws
    /// Schedules an app-level notification that is not a Reminder occurrence.
    func scheduleAppNotification(_ request: ScheduledAppNotificationRequest) async throws
    func cancel(identifiers: [String]) async
    func pendingIdentifiers(prefix: String) async -> [String]
}

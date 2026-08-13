import Foundation

/// Outcome of rebuilding local notifications for all active reminders.
enum NotificationReconcileResult: Equatable, Sendable {
    case success
    case permissionDenied
    case persistenceFailure
    case schedulingFailure
}

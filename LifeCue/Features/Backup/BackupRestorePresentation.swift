import Foundation

enum BackupRestorePresentation {
    static var restoreSuccessWithNotifications: String {
        "Restore completed. Your reminders were restored and notifications were rebuilt."
    }

    static var restoreSuccessWithoutNotifications: String {
        "Restore completed, but some notifications could not be scheduled. Check notification settings and try again."
    }

    static func restoreMessage(for result: NotificationReconcileResult) -> String {
        switch result {
        case .success:
            return restoreSuccessWithNotifications
        case .permissionDenied, .schedulingFailure, .persistenceFailure:
            return restoreSuccessWithoutNotifications
        }
    }
}

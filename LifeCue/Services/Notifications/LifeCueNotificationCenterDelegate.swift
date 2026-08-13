import Foundation
import UserNotifications

/// Presents local notifications while LifeCue is in the foreground,
/// and routes notification taps to ReminderDetailView via `NotificationNavigationStore`.
/// Scheduling remains in `UserNotificationScheduler` / `ReminderService`.
final class LifeCueNotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate {
    /// Visible foreground presentation for iOS 17+ (deployment target).
    static let foregroundPresentationOptions: UNNotificationPresentationOptions = [
        .banner,
        .sound,
        .badge
    ]

    /// Navigation target for tap handling. Retained by the app; never temporary.
    private let navigationStore: NotificationNavigationStore

    init(navigationStore: NotificationNavigationStore) {
        self.navigationStore = navigationStore
        super.init()
    }

    /// Assigns this instance as the shared notification center delegate.
    /// Call once at launch and retain `delegate` for the app lifetime.
    static func install(_ delegate: LifeCueNotificationCenterDelegate) {
        UNUserNotificationCenter.current().delegate = delegate
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundPresentationOptions)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        if BackupReminderNotification.isBackupReminder(
            requestIdentifier: request.identifier,
            userInfo: request.content.userInfo
        ) {
            Task { @MainActor in
                navigationStore.enqueueBackupRestoreOpen()
                completionHandler()
            }
            return
        }
        let reminderID = NotificationTapRouting.reminderID(
            requestIdentifier: request.identifier,
            userInfo: request.content.userInfo
        )
        Task { @MainActor in
            navigationStore.enqueue(reminderID: reminderID)
            completionHandler()
        }
    }
}

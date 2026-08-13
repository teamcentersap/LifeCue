import Foundation
import UserNotifications

/// Production scheduler wrapping UNUserNotificationCenter.
@MainActor
final class UserNotificationScheduler: NotificationScheduling {
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let didAskKey = "lifecue.notifications.didAskAuthorization"

    init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard
    ) {
        self.center = center
        self.defaults = defaults
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unsupported
        }
    }

    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationStatus {
        let current = await authorizationStatus()
        switch current {
        case .authorized, .provisional, .ephemeral:
            return current
        case .denied, .unsupported:
            return current
        case .notDetermined:
            if defaults.bool(forKey: didAskKey) {
                return current
            }
            defaults.set(true, forKey: didAskKey)
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                return granted ? .authorized : .denied
            } catch {
                return .denied
            }
        }
    }

    func scheduleAppNotification(_ request: ScheduledAppNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = request.userInfo

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: request.fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let unRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(unRequest)
    }

    func schedule(_ request: ScheduledNotificationRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        content.userInfo = [
            "reminderID": request.reminderID.uuidString,
            "ruleID": request.ruleID?.uuidString as Any,
            "occurrenceKey": request.occurrenceKey as Any
        ]

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.timeZoneIdentifier) ?? .current
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: request.fireAt
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let unRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(unRequest)
    }

    func cancel(identifiers: [String]) async {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func pendingIdentifiers(prefix: String) async -> [String] {
        let pending = await center.pendingNotificationRequests()
        return pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
    }
}

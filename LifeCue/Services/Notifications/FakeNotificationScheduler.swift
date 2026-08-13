import Foundation

/// In-memory fake for unit tests. No UserNotifications dependency.
@MainActor
final class FakeNotificationScheduler: NotificationScheduling {
    var status: NotificationAuthorizationStatus = .authorized
    var didRequestAuthorization = false
    var shouldFailSchedule = false
    private(set) var scheduled: [ScheduledNotificationRequest] = []
    private(set) var scheduledApp: [ScheduledAppNotificationRequest] = []
    private(set) var cancelledIdentifiers: [String] = []

    enum FakeError: Error {
        case forcedFailure
    }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        status
    }

    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationStatus {
        didRequestAuthorization = true
        if status == .notDetermined {
            status = .authorized
        }
        return status
    }

    func scheduleAppNotification(_ request: ScheduledAppNotificationRequest) async throws {
        if shouldFailSchedule { throw FakeError.forcedFailure }
        scheduledApp.removeAll { $0.identifier == request.identifier }
        scheduledApp.append(request)
    }

    func schedule(_ request: ScheduledNotificationRequest) async throws {
        if shouldFailSchedule { throw FakeError.forcedFailure }
        scheduled.removeAll { $0.identifier == request.identifier }
        scheduled.append(request)
    }

    func cancel(identifiers: [String]) async {
        cancelledIdentifiers.append(contentsOf: identifiers)
        scheduled.removeAll { identifiers.contains($0.identifier) }
        scheduledApp.removeAll { identifiers.contains($0.identifier) }
    }

    func pendingIdentifiers(prefix: String) async -> [String] {
        let reminderIDs = scheduled.map(\.identifier).filter { $0.hasPrefix(prefix) }
        let appIDs = scheduledApp.map(\.identifier).filter { $0.hasPrefix(prefix) }
        return reminderIDs + appIDs
    }

    func reset() {
        scheduled.removeAll()
        scheduledApp.removeAll()
        cancelledIdentifiers.removeAll()
        didRequestAuthorization = false
        shouldFailSchedule = false
    }
}

import Foundation

/// Test double that can pause inside `schedule` so races are deterministic.
///
/// Flow:
/// 1. `shouldPauseSchedules = true`
/// 2. Start a scheduling operation (it suspends inside `schedule`)
/// 3. Await `waitUntilPaused()`
/// 4. Perform Complete/Delete/Edit
/// 5. `releasePausedSchedules()`
@MainActor
final class DelayedNotificationScheduler: NotificationScheduling {
    let backing: FakeNotificationScheduler

    /// When true, each `schedule` call suspends before adding to the backing store.
    var shouldPauseSchedules = false

    private var pauseContinuations: [CheckedContinuation<Void, Never>] = []

    init(backing: FakeNotificationScheduler) {
        self.backing = backing
    }

    convenience init() {
        self.init(backing: FakeNotificationScheduler())
    }

    var scheduled: [ScheduledNotificationRequest] { backing.scheduled }
    var scheduledApp: [ScheduledAppNotificationRequest] { backing.scheduledApp }
    var cancelledIdentifiers: [String] { backing.cancelledIdentifiers }
    var status: NotificationAuthorizationStatus {
        get { backing.status }
        set { backing.status = newValue }
    }

    var pausedScheduleCount: Int { pauseContinuations.count }

    func authorizationStatus() async -> NotificationAuthorizationStatus {
        await backing.authorizationStatus()
    }

    func requestAuthorizationIfNeeded() async -> NotificationAuthorizationStatus {
        await backing.requestAuthorizationIfNeeded()
    }

    func scheduleAppNotification(_ request: ScheduledAppNotificationRequest) async throws {
        if shouldPauseSchedules {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                pauseContinuations.append(continuation)
            }
        }
        try await backing.scheduleAppNotification(request)
    }

    func schedule(_ request: ScheduledNotificationRequest) async throws {
        if shouldPauseSchedules {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                pauseContinuations.append(continuation)
            }
        }
        try await backing.schedule(request)
    }

    func cancel(identifiers: [String]) async {
        await backing.cancel(identifiers: identifiers)
    }

    func pendingIdentifiers(prefix: String) async -> [String] {
        await backing.pendingIdentifiers(prefix: prefix)
    }

    /// Suspends until at least `count` schedule calls are paused (or timeout).
    func waitUntilPaused(count: Int = 1, timeoutNanoseconds: UInt64 = 5_000_000_000) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while pausedScheduleCount < count {
            if DispatchTime.now().uptimeNanoseconds > deadline {
                return false
            }
            await Task.yield()
        }
        return true
    }

    func releasePausedSchedules() {
        let pending = pauseContinuations
        pauseContinuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    func reset() {
        shouldPauseSchedules = false
        releasePausedSchedules()
        backing.reset()
    }
}

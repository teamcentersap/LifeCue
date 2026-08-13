import Foundation
import Observation

/// App-level pending navigation from a notification tap.
/// Presentation-only — never schedules or mutates reminders.
@MainActor
@Observable
final class NotificationNavigationStore {
    /// Set when a notification is tapped; consumed by Home once navigation is ready.
    private(set) var pendingReminderID: UUID?
    /// True when the backup reminder notification was tapped.
    private(set) var pendingOpenBackupRestore = false
    /// True when the tap could not resolve a Reminder ID (missing/invalid payload).
    private(set) var pendingUnavailable = false
    /// Generation token so repeated taps of the same ID still trigger observers.
    private(set) var pendingGeneration: UInt64 = 0

    func enqueue(reminderID: UUID?) {
        pendingGeneration &+= 1
        pendingOpenBackupRestore = false
        if let reminderID {
            pendingReminderID = reminderID
            pendingUnavailable = false
        } else {
            pendingReminderID = nil
            pendingUnavailable = true
        }
    }

    func enqueueBackupRestoreOpen() {
        pendingGeneration &+= 1
        pendingOpenBackupRestore = true
        pendingReminderID = nil
        pendingUnavailable = false
    }

    /// Clears pending open after Home has attempted navigation.
    func consumePendingOpen() {
        pendingReminderID = nil
    }

    func consumePendingBackupRestore() {
        pendingOpenBackupRestore = false
    }

    func consumeUnavailable() {
        pendingUnavailable = false
    }
}

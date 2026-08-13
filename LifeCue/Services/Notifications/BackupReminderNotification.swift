import Foundation

/// Application-level backup reminder notification (not a Reminder record).
enum BackupReminderNotification {
    static let identifier = "lifecue.backupReminder"

    static let userInfoTypeKey = "type"
    static let userInfoTypeValue = "backupReminder"

    static let title = "Protect your LifeCue data"
    static let body = "You haven't created a backup recently. Export a backup to keep your reminders safe."

    /// Fixed local fire time for backup reminders (device timezone).
    static let fireTimeHour = 9
    static let fireTimeMinute = 0

    static func isBackupReminder(
        requestIdentifier: String,
        userInfo: [AnyHashable: Any]
    ) -> Bool {
        if requestIdentifier == identifier { return true }
        return userInfo[userInfoTypeKey] as? String == userInfoTypeValue
    }
}

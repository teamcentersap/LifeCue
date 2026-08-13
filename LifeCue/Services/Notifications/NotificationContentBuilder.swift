import Foundation

enum NotificationContentBuilder {
    static func title(for reminder: Reminder) -> String {
        reminder.trimmedTitle
    }

    /// Keep body short. Person is not available yet.
    static func body(for reminder: Reminder, calendar: Calendar? = nil) -> String {
        _ = calendar
        if let time = ReminderDisplayFormatter.timeString(for: reminder) {
            return "\(ReminderDisplayFormatter.dateString(for: reminder)) · \(time)"
        }
        return ReminderDisplayFormatter.dateString(for: reminder)
    }
}

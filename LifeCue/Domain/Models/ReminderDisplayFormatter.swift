import Foundation

enum ReminderDisplayFormatter {
    /// User-facing calendar date in the established LifeCue style (`dateStyle: .medium`),
    /// e.g. "25 Aug 2026" / "3 Sep 2026" depending on locale.
    static func dateString(from date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = .current
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    static func dateString(for reminder: Reminder) -> String {
        let calendar = reminder.calendarInStoredTimeZone()
        guard let date = calendar.date(from: Reminder.normalizedDate(reminder.eventDate)) else {
            return "Unknown date"
        }
        return dateString(from: date, calendar: calendar)
    }

    static func timeString(for reminder: Reminder) -> String? {
        guard let eventTime = reminder.eventTime,
              let hour = eventTime.hour,
              let minute = eventTime.minute else {
            return nil
        }

        let calendar = reminder.calendarInStoredTimeZone()
        var components = Reminder.normalizedDate(reminder.eventDate)
        components.hour = hour
        components.minute = minute
        components.second = 0
        guard let date = calendar.date(from: components) else { return nil }

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    static func subtitle(for reminder: Reminder) -> String {
        let date = dateString(for: reminder)
        if let time = timeString(for: reminder) {
            return "\(date) · \(time)"
        }
        return date
    }
}

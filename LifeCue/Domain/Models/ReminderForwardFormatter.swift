import Foundation

/// Deterministic Reminder → plain-text for the Forward action.
/// Pure: no SwiftUI, OCR, persistence, or notification scheduling.
enum ReminderForwardFormatter {
    /// Builds human-readable forward text.
    /// - Parameters:
    ///   - reminder: Structured reminder (schedule uses stored timezone).
    ///   - personName: Already-resolved display name (may include "(archived)").
    ///   - contextName: Already-resolved display name (may include "(archived)").
    static func makeText(
        for reminder: Reminder,
        personName: String? = nil,
        contextName: String? = nil
    ) -> String {
        var lines: [String] = []
        lines.append(reminder.trimmedTitle)
        lines.append("")

        let recurring = reminder.standingRules.first {
            $0.enabled && $0.ruleType == .recurring
        }

        if let recurring, let recurrence = recurring.recurrence {
            lines.append(contentsOf: recurringScheduleLines(
                reminder: reminder,
                recurrence: recurrence,
                window: recurring.dateWindow
            ))
        } else {
            lines.append("Date: \(longDateString(for: reminder))")
            if let time = ReminderDisplayFormatter.timeString(for: reminder) {
                lines.append("Time: \(time)")
            }
        }

        if let personName, !personName.isEmpty {
            lines.append("For: \(personName)")
        }
        if let contextName, !contextName.isEmpty {
            lines.append("Context: \(contextName)")
        }

        if let note = Reminder.normalizedNote(reminder.note) {
            lines.append("")
            lines.append("Note:")
            lines.append(note)
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Recurrence

    private static func recurringScheduleLines(
        reminder: Reminder,
        recurrence: ReminderRecurrence,
        window: ReminderDateWindow?
    ) -> [String] {
        var base: String
        switch recurrence.frequency {
        case .daily:
            base = "Every day"
        case .weekly:
            let days = (recurrence.weekdays ?? []).sorted()
            if days == [2, 3, 4, 5, 6] {
                base = "Every weekday"
            } else if days.count == 1, let day = days.first {
                base = "Every \(weekdayName(day))"
            } else if !days.isEmpty {
                base = "Every " + days.map(weekdayName).joined(separator: ", ")
            } else {
                base = "Every week"
            }
        case .monthly:
            let day = recurrence.dayOfMonth ?? reminder.eventDate.day
            if let day {
                base = "Every month on the \(day)"
            } else {
                base = "Every month"
            }
        case .yearly:
            if let month = reminder.eventDate.month, let day = reminder.eventDate.day {
                base = "Every year on \(monthName(month)) \(day)"
            } else {
                base = "Every year"
            }
        }

        if let time = ReminderDisplayFormatter.timeString(for: reminder) {
            base += " at \(time)"
        }

        var lines = [base]
        if let window {
            lines.append("From: \(longDateComponents(window.startDate, timeZoneIdentifier: reminder.timeZoneIdentifier))")
            lines.append("Until: \(longDateComponents(window.endDate, timeZoneIdentifier: reminder.timeZoneIdentifier))")
        }
        return lines
    }

    // MARK: - Date helpers

    private static func longDateString(for reminder: Reminder) -> String {
        longDateComponents(reminder.eventDate, timeZoneIdentifier: reminder.timeZoneIdentifier)
    }

    private static func longDateComponents(
        _ components: DateComponents,
        timeZoneIdentifier: String
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        guard let date = calendar.date(from: Reminder.normalizedDate(components)) else {
            let d = components.day ?? 0
            let m = components.month.map(monthName) ?? "?"
            let y = components.year.map(String.init) ?? ""
            return [String(d), m, y].filter { !$0.isEmpty }.joined(separator: " ")
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMMM yyyy"
        return formatter.string(from: date)
    }

    private static func weekdayName(_ weekday: Int) -> String {
        let names = ["", "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        guard (1...7).contains(weekday) else { return "day" }
        return names[weekday]
    }

    private static func monthName(_ month: Int) -> String {
        let names = [
            "", "January", "February", "March", "April", "May", "June",
            "July", "August", "September", "October", "November", "December"
        ]
        guard (1...12).contains(month) else { return "month" }
        return names[month]
    }
}

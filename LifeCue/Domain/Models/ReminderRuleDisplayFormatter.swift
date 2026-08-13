import Foundation

enum ReminderRuleDisplayFormatter {
    static func summary(for reminder: Reminder) -> String {
        let standing = reminder.rules.filter { $0.enabled && $0.ruleType != .snoozeOneOff }
        var parts = standing.map { label(for: $0, reminder: reminder) }
        if let snooze = reminder.snooze {
            parts.append("Snoozed until \(shortTime(snooze.until, timeZoneIdentifier: reminder.timeZoneIdentifier))")
        }
        if parts.isEmpty { return "No reminders scheduled" }
        return parts.joined(separator: " · ")
    }

    static func summary(for rules: [ReminderRule]) -> String {
        let standing = rules.filter { $0.enabled && $0.ruleType != .snoozeOneOff }
        if standing.isEmpty { return "No reminders scheduled" }
        return standing.map { label(for: $0, reminder: nil) }.joined(separator: " · ")
    }

    static func label(for rule: ReminderRule, reminder: Reminder? = nil) -> String {
        switch rule.ruleType {
        case .exactAtEvent:
            return "At event time"
        case .beforeEvent:
            guard let value = rule.offsetValue, let unit = rule.offsetUnit else {
                return "Before event"
            }
            return "\(value) \(unitLabel(unit, value: value)) before"
        case .snoozeOneOff:
            return "Snoozed"
        case .recurring:
            return recurrenceLabel(rule.recurrence, window: rule.dateWindow, reminder: reminder)
        case .dateWindow:
            return "Date window"
        }
    }

    private static func recurrenceLabel(
        _ recurrence: ReminderRecurrence?,
        window: ReminderDateWindow?,
        reminder: Reminder?
    ) -> String {
        guard let recurrence else { return "Repeats" }
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
            let day = recurrence.dayOfMonth ?? reminder?.eventDate.day
            if let day {
                base = "Every month on the \(day)"
            } else {
                base = "Every month"
            }
        case .yearly:
            if let reminder,
               let month = reminder.eventDate.month,
               let day = reminder.eventDate.day {
                base = "Every year on \(monthName(month)) \(day)"
            } else {
                base = "Every year"
            }
        }
        if let window {
            base += " from \(shortDate(window.startDate)) to \(shortDate(window.endDate))"
        }
        return base
    }

    private static func weekdayName(_ weekday: Int) -> String {
        // Calendar: 1=Sun … 7=Sat
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

    private static func shortDate(_ comps: DateComponents) -> String {
        let d = comps.day ?? 0
        let m = comps.month.map(monthName) ?? "?"
        if let y = comps.year {
            return "\(d) \(m) \(y)"
        }
        return "\(d) \(m)"
    }

    private static func unitLabel(_ unit: ReminderOffsetUnit, value: Int) -> String {
        let plural = value == 1 ? "" : "s"
        switch unit {
        case .minute: return "minute\(plural)"
        case .hour: return "hour\(plural)"
        case .day: return "day\(plural)"
        case .week: return "week\(plural)"
        case .month: return "month\(plural)"
        }
    }

    private static func shortTime(_ date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

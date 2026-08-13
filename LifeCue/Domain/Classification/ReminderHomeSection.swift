import Foundation

/// Home list buckets for active reminders.
enum ReminderHomeSection: String, CaseIterable, Identifiable, Sendable {
    case overdue
    case today
    case upcoming

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: return "Overdue"
        case .today: return "Today"
        case .upcoming: return "Upcoming"
        }
    }
}

/// Pure classification of reminders for the Home screen.
struct ReminderHomeClassifier: Sendable {
    var calendar: Calendar
    var now: Date

    init(calendar: Calendar = .current, now: Date = Date()) {
        self.calendar = calendar
        self.now = now
    }

    func section(for reminder: Reminder) -> ReminderHomeSection? {
        guard reminder.status == .active else { return nil }
        guard let eventDay = eventDayDate(for: reminder) else { return nil }

        let todayStart = calendar.startOfDay(for: now)
        let eventStart = calendar.startOfDay(for: eventDay)

        if eventStart < todayStart {
            return .overdue
        }
        if calendar.isDate(eventStart, inSameDayAs: todayStart) {
            return .today
        }
        return .upcoming
    }

    func grouped(_ reminders: [Reminder]) -> [ReminderHomeSection: [Reminder]] {
        var result: [ReminderHomeSection: [Reminder]] = [
            .overdue: [],
            .today: [],
            .upcoming: []
        ]

        for reminder in reminders {
            guard let section = section(for: reminder) else { continue }
            result[section, default: []].append(reminder)
        }

        for section in ReminderHomeSection.allCases {
            result[section] = (result[section] ?? []).sorted(by: sortAscending)
        }

        return result
    }

    private func sortAscending(_ lhs: Reminder, _ rhs: Reminder) -> Bool {
        let left = lhs.sortDate(calendar: calendar) ?? .distantFuture
        let right = rhs.sortDate(calendar: calendar) ?? .distantFuture
        if left != right { return left < right }
        return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
    }

    private func eventDayDate(for reminder: Reminder) -> Date? {
        var calendar = calendar
        if let timeZone = TimeZone(identifier: reminder.timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }
        return calendar.date(from: Reminder.normalizedDate(reminder.eventDate))
    }
}

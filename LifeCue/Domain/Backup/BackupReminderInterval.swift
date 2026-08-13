import Foundation

/// Typed intervals for the optional Backup Reminder notification.
enum BackupReminderInterval: String, CaseIterable, Codable, Sendable, Equatable {
    case oneWeek
    case twoWeeks
    case oneMonth
    case threeMonths

    var displayName: String {
        switch self {
        case .oneWeek: return "1 week"
        case .twoWeeks: return "2 weeks"
        case .oneMonth: return "1 month"
        case .threeMonths: return "3 months"
        }
    }

    /// Adds this interval to `date` using calendar-aware math (months use `.month`).
    func adding(to date: Date, calendar: Calendar) -> Date {
        switch self {
        case .oneWeek:
            return calendar.date(byAdding: .day, value: 7, to: date) ?? date
        case .twoWeeks:
            return calendar.date(byAdding: .day, value: 14, to: date) ?? date
        case .oneMonth:
            return calendar.date(byAdding: .month, value: 1, to: date) ?? date
        case .threeMonths:
            return calendar.date(byAdding: .month, value: 3, to: date) ?? date
        }
    }
}

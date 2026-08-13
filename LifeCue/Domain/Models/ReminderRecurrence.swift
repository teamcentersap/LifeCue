import Foundation

/// How often a recurring standing rule repeats.
enum ReminderRecurrenceFrequency: String, Codable, CaseIterable, Sendable {
    case daily
    case weekly
    case monthly
    case yearly
}

/// Typed recurrence configuration. Never an opaque RRULE string.
struct ReminderRecurrence: Equatable, Sendable, Codable {
    var frequency: ReminderRecurrenceFrequency
    /// Every N periods (V1 UI uses 1).
    var interval: Int
    /// Calendar weekdays: 1 = Sunday … 7 = Saturday (`Calendar` convention).
    /// Required for weekly when non-empty; empty/nil means use the reminder event weekday.
    var weekdays: [Int]?
    /// Day-of-month for monthly (1…31). Nil → use reminder `eventDate.day`.
    var dayOfMonth: Int?

    init(
        frequency: ReminderRecurrenceFrequency,
        interval: Int = 1,
        weekdays: [Int]? = nil,
        dayOfMonth: Int? = nil
    ) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
    }

    static func daily(interval: Int = 1) -> ReminderRecurrence {
        ReminderRecurrence(frequency: .daily, interval: interval)
    }

    static func weekly(weekdays: [Int], interval: Int = 1) -> ReminderRecurrence {
        ReminderRecurrence(frequency: .weekly, interval: interval, weekdays: weekdays)
    }

    static func monthly(dayOfMonth: Int, interval: Int = 1) -> ReminderRecurrence {
        ReminderRecurrence(frequency: .monthly, interval: interval, dayOfMonth: dayOfMonth)
    }

    static func yearly(interval: Int = 1) -> ReminderRecurrence {
        ReminderRecurrence(frequency: .yearly, interval: interval)
    }
}

/// Inclusive calendar-day window restricting recurrence anchors.
struct ReminderDateWindow: Equatable, Sendable, Codable {
    /// Year/month/day in the reminder timezone.
    var startDate: DateComponents
    var endDate: DateComponents

    init(startDate: DateComponents, endDate: DateComponents) {
        self.startDate = DateComponents(
            year: startDate.year,
            month: startDate.month,
            day: startDate.day
        )
        self.endDate = DateComponents(
            year: endDate.year,
            month: endDate.month,
            day: endDate.day
        )
    }
}

enum ReminderRuleValidationError: Error, Equatable, LocalizedError {
    case invalidDateWindow
    case invalidRecurrence
    case invalidWeekdays
    case invalidDayOfMonth

    var errorDescription: String? {
        switch self {
        case .invalidDateWindow:
            return "End date must be on or after the start date."
        case .invalidRecurrence:
            return "That repeat schedule isn't valid."
        case .invalidWeekdays:
            return "Choose at least one day of the week."
        case .invalidDayOfMonth:
            return "Choose a day between 1 and 31."
        }
    }
}

enum ReminderRuleValidator {
    static func validate(_ rule: ReminderRule, calendar: Calendar = Calendar(identifier: .gregorian)) throws {
        if let window = rule.dateWindow {
            try validate(window: window, calendar: calendar)
        }
        if rule.ruleType == .recurring {
            guard let recurrence = rule.recurrence else {
                throw ReminderRuleValidationError.invalidRecurrence
            }
            try validate(recurrence: recurrence)
        }
    }

    static func validate(window: ReminderDateWindow, calendar: Calendar) throws {
        guard let start = calendar.date(from: DateComponents(
            year: window.startDate.year,
            month: window.startDate.month,
            day: window.startDate.day,
            hour: 12
        )),
        let end = calendar.date(from: DateComponents(
            year: window.endDate.year,
            month: window.endDate.month,
            day: window.endDate.day,
            hour: 12
        ))
        else {
            throw ReminderRuleValidationError.invalidDateWindow
        }
        guard start <= end else {
            throw ReminderRuleValidationError.invalidDateWindow
        }
    }

    static func validate(recurrence: ReminderRecurrence) throws {
        guard recurrence.interval >= 1 else {
            throw ReminderRuleValidationError.invalidRecurrence
        }
        switch recurrence.frequency {
        case .weekly:
            let days = recurrence.weekdays ?? []
            guard !days.isEmpty, days.allSatisfy({ (1...7).contains($0) }) else {
                throw ReminderRuleValidationError.invalidWeekdays
            }
        case .monthly:
            if let day = recurrence.dayOfMonth, !(1...31).contains(day) {
                throw ReminderRuleValidationError.invalidDayOfMonth
            }
        case .daily, .yearly:
            break
        }
    }

    static func validate(rules: [ReminderRule], calendar: Calendar = Calendar(identifier: .gregorian)) throws {
        for rule in rules where rule.enabled {
            try validate(rule, calendar: calendar)
        }
    }
}

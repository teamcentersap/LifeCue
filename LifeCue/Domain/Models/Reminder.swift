import Foundation

/// Domain reminder. Dates and times are typed — never display strings.
struct Reminder: Identifiable, Equatable, Sendable {
    let id: UUID
    var title: String
    /// Calendar date of the event/due day (year, month, day). Time is separate.
    var eventDate: DateComponents
    /// Optional wall-clock time (hour, minute).
    /// Nil means date-only: scheduling uses `ReminderSchedulingPolicy.defaultTimeOfDay` (V1: 09:00).
    var eventTime: DateComponents?
    /// Authoritative timezone for this reminder's wall-clock date/time.
    var timeZoneIdentifier: String
    var note: String?
    /// Optional Person reference. Nil = not for anyone specific.
    var personID: UUID?
    /// Optional Context reference. Nil = no organizational label.
    var contextID: UUID?
    var status: ReminderStatus
    /// Standing schedule rules. Empty means no standing notifications.
    var rules: [ReminderRule]
    /// Temporary snooze state. Does not mutate or replace `rules`.
    var snooze: ReminderSnoozeState?
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        eventDate: DateComponents,
        eventTime: DateComponents? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        note: String? = nil,
        personID: UUID? = nil,
        contextID: UUID? = nil,
        status: ReminderStatus = .active,
        rules: [ReminderRule] = [],
        snooze: ReminderSnoozeState? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.eventDate = Self.normalizedDate(eventDate)
        self.eventTime = eventTime.map(Self.normalizedTime)
        self.timeZoneIdentifier = timeZoneIdentifier
        self.note = Self.normalizedNote(note)
        self.personID = personID
        self.contextID = contextID
        self.status = status
        self.rules = rules.filter { $0.ruleType != .snoozeOneOff }
        self.snooze = snooze
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasNote: Bool {
        guard let note else { return false }
        return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Standing schedule only (alias for clarity after separating snooze).
    var standingRules: [ReminderRule] { rules }

    /// Calendar configured for this reminder's stored timezone.
    func calendarInStoredTimeZone(
        template: Calendar = Calendar(identifier: .gregorian)
    ) -> Calendar {
        var calendar = template
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    /// Instant used for ordering and sectioning when a time is present; otherwise start of event day.
    func sortDate(calendar: Calendar = .current) -> Date? {
        let calendar = calendarInStoredTimeZone(template: calendar)
        var components = eventDate
        if let eventTime {
            components.hour = eventTime.hour
            components.minute = eventTime.minute
            components.second = 0
        } else {
            components.hour = 0
            components.minute = 0
            components.second = 0
        }
        return calendar.date(from: components)
    }

    static func normalizedDate(_ components: DateComponents) -> DateComponents {
        DateComponents(
            year: components.year,
            month: components.month,
            day: components.day
        )
    }

    static func normalizedTime(_ components: DateComponents) -> DateComponents {
        DateComponents(
            hour: components.hour,
            minute: components.minute
        )
    }

    static func normalizedNote(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func dateComponents(from date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.year, .month, .day], from: date)
    }

    static func timeComponents(from date: Date, calendar: Calendar) -> DateComponents {
        calendar.dateComponents([.hour, .minute], from: date)
    }
}

enum ReminderValidationError: Error, Equatable, LocalizedError {
    case emptyTitle
    case missingEventDate
    case activeReminderLimitReached(limit: Int)
    case invalidPerson
    case invalidContext

    var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "Title is required."
        case .missingEventDate:
            return "A date is required."
        case .activeReminderLimitReached(let limit):
            return "You've reached the limit of \(limit) active reminders. Complete or delete an existing reminder to add a new one."
        case .invalidPerson:
            return "That person isn't available."
        case .invalidContext:
            return "That context isn't available."
        }
    }
}

/// Outcome of attempting to sync local notifications after a successful persistence write.
enum ReminderScheduleOutcome: Equatable, Sendable {
    case scheduled(Int)
    case nothingToSchedule
    case permissionDenied
    case schedulingFailed
    case superseded
}

struct ReminderMutationResult: Equatable, Sendable {
    let reminder: Reminder
    let scheduleOutcome: ReminderScheduleOutcome

    var didPersist: Bool { true }

    var scheduleFailed: Bool {
        if case .schedulingFailed = scheduleOutcome { return true }
        return false
    }
}

enum ReminderFactory {
    static func make(
        title: String,
        eventDate: DateComponents,
        eventTime: DateComponents? = nil,
        timeZoneIdentifier: String = TimeZone.current.identifier,
        note: String? = nil,
        personID: UUID? = nil,
        contextID: UUID? = nil,
        rules: [ReminderRule] = [],
        snooze: ReminderSnoozeState? = nil,
        now: Date = Date()
    ) throws -> Reminder {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw ReminderValidationError.emptyTitle }
        guard eventDate.year != nil, eventDate.month != nil, eventDate.day != nil else {
            throw ReminderValidationError.missingEventDate
        }

        return Reminder(
            title: trimmedTitle,
            eventDate: eventDate,
            eventTime: eventTime,
            timeZoneIdentifier: timeZoneIdentifier,
            note: note,
            personID: personID,
            contextID: contextID,
            status: .active,
            rules: rules,
            snooze: snooze,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
    }
}

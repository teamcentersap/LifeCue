import Foundation

/// Optional recurrence hint only. Never becomes a ReminderRule without user confirmation (Sprint 5+).
enum DraftRecurrenceHint: String, Equatable, Sendable {
    case yearly
    case weekly
}

/// Unconfirmed extraction from OCR text. Independent from `Reminder`.
struct ReminderDraft: Equatable, Sendable {
    var title: String
    /// True when title is a safe fallback rather than text found in the OCR.
    var titleWasFallback: Bool
    var dateState: ExtractionFieldState<DateComponents>
    var timeState: ExtractionFieldState<DateComponents>
    var note: String?
    var personName: String?
    var contextName: String?
    /// Explicit user selection at confirm time (Sprint 7). Not inferred from OCR.
    var personID: UUID?
    var contextID: UUID?
    var proposedRecurrence: DraftRecurrenceHint?
    /// Wall-clock timezone used when combining date + time (from extraction config).
    var timeZoneIdentifier: String
    var localeIdentifier: String
    /// Original OCR text used for extraction (for Sprint 5 review context).
    var sourceText: String

    /// Confidently resolved event date, if any.
    var eventDate: DateComponents? { dateState.resolvedValue }

    /// Confidently resolved event time, if any.
    var eventTime: DateComponents? { timeState.resolvedValue }

    var hasResolvedDate: Bool { eventDate != nil }
    var hasResolvedTime: Bool { eventTime != nil }

    static let fallbackTitle = "New Reminder"

    static func empty(sourceText: String, configuration: ExtractionConfiguration) -> ReminderDraft {
        ReminderDraft(
            title: fallbackTitle,
            titleWasFallback: true,
            dateState: .missing,
            timeState: .missing,
            note: nil,
            personName: nil,
            contextName: nil,
            personID: nil,
            contextID: nil,
            proposedRecurrence: nil,
            timeZoneIdentifier: configuration.timeZone.identifier,
            localeIdentifier: configuration.locale.identifier,
            sourceText: sourceText
        )
    }
}

/// Explicit extraction context. Never uses ambient `Date()` inside parsers.
struct ExtractionConfiguration: Equatable, Sendable {
    /// Instant whose calendar day is the reference for relative dates.
    let referenceDate: Date
    let timeZone: TimeZone
    let locale: Locale

    init(
        referenceDate: Date,
        timeZone: TimeZone,
        locale: Locale
    ) {
        self.referenceDate = referenceDate
        self.timeZone = timeZone
        self.locale = locale
    }

    /// Gregorian calendar pinned to the configured timezone and locale.
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        calendar.locale = locale
        return calendar
    }

    /// Whether the locale prefers month-first numeric dates (en_US) vs day-first (en_GB, en_IN).
    var prefersMonthFirstNumericDates: Bool {
        let format = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: locale) ?? "dd/MM"
        // If 'M' appears before 'd' in the template output, month-first.
        guard let m = format.firstIndex(of: "M"), let d = format.firstIndex(of: "d") else {
            return false
        }
        return m < d
    }
}

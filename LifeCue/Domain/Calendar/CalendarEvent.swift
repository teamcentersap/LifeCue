import Foundation

/// Lightweight domain model for read-only Calendar context.
/// This intentionally does NOT expose EventKit types.
struct CalendarEvent: Identifiable, Equatable, Sendable {
    /// Stable identifier for matching within a single fetch.
    let id: String
    let title: String

    /// Absolute start/end instants returned by the service.
    /// For all-day events, `startDate` represents the start day in the event time zone.
    let startDate: Date
    let endDate: Date

    let isAllDay: Bool
    let calendarName: String
    /// Calendar identifier (EKCalendar.calendarIdentifier) when available.
    let calendarIdentifier: String?

    /// Time zone identifier that represents the event’s wall-clock time.
    /// (Where available from EventKit; never derived from device time zone.)
    let timeZoneIdentifier: String
}


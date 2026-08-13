import Foundation

/// Transforms a `CalendarEvent` into Reminder-compatible prefill values.
/// Pure/deterministic: does not create or mutate reminders.
enum CalendarEventPrefill {
    struct Result: Equatable {
        let title: String
        let eventDate: Date
        let includeTime: Bool
        let eventTime: Date
        let reminderTimeZoneIdentifier: String
    }

    static func makePrefill(from event: CalendarEvent) -> Result {
        let tz = TimeZone(identifier: event.timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz

        let dayStart = calendar.startOfDay(for: event.startDate)

        if event.isAllDay {
            return Result(
                title: event.title,
                eventDate: dayStart,
                includeTime: false,
                eventTime: dayStart,
                reminderTimeZoneIdentifier: tz.identifier
            )
        }

        // Preserve wall-clock hour/minute in the event’s time zone.
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: event.startDate)
        var dayComps = DateComponents(year: comps.year, month: comps.month, day: comps.day)
        dayComps.hour = comps.hour
        dayComps.minute = comps.minute
        dayComps.second = 0
        let eventInstant = calendar.date(from: dayComps) ?? event.startDate

        return Result(
            title: event.title,
            eventDate: dayStart,
            includeTime: true,
            eventTime: eventInstant,
            reminderTimeZoneIdentifier: tz.identifier
        )
    }
}


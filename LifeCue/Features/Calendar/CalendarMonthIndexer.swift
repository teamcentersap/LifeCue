import Foundation

/// Maps active LifeCue reminders onto calendar day keys for the month view.
/// Reuses `ReminderRuleEngine` for recurrence / date-window — does not reimplement rules.
enum CalendarMonthReminderIndexer {
    /// Display-only capacity so a full month of daily occurrences can appear on the grid.
    /// Does not affect notification scheduling policy.
    static let displayPolicy = ReminderSchedulingPolicy(
        defaultTimeOfDay: ReminderSchedulingPolicy.default.defaultTimeOfDay,
        maxOccurrencesPerReminder: 62,
        horizonDays: ReminderSchedulingPolicy.default.horizonDays,
        maxActiveReminders: ReminderSchedulingPolicy.default.maxActiveReminders,
        maxPendingNotifications: ReminderSchedulingPolicy.default.maxPendingNotifications
    )

    /// Days that should show a LifeCue reminder indicator within `visibleDays`.
    static func indicatorDays(
        for reminder: Reminder,
        visibleDays: Set<CalendarDayComponents>,
        rangeStart: Date,
        engine: ReminderRuleEngine? = nil
    ) -> Set<CalendarDayComponents> {
        guard reminder.status == .active else { return [] }
        guard !visibleDays.isEmpty else { return [] }

        let engine = engine ?? ReminderRuleEngine(policy: displayPolicy)
        let hasRecurring = reminder.rules.contains { $0.enabled && $0.ruleType == .recurring }
        if hasRecurring {
            // Probe just before the visible range so the engine includes in-range anchors.
            let probeNow = rangeStart.addingTimeInterval(-1)
            let occurrences = engine.occurrences(for: reminder, now: probeNow, onlyFuture: true)
            let remCal = reminder.calendarInStoredTimeZone(template: engine.calendar)
            var days = Set<CalendarDayComponents>()
            for occurrence in occurrences {
                // Calendar shows event/occurrence days, not "N before" notification offsets.
                guard occurrence.ruleType == .recurring || occurrence.ruleType == .exactAtEvent else {
                    continue
                }
                guard let day = CalendarDayComponents.from(date: occurrence.fireAt, calendar: remCal),
                      visibleDays.contains(day)
                else { continue }
                days.insert(day)
            }
            return days
        }

        // One-shot / non-recurring: indicator on the reminder's stored event date.
        guard let year = reminder.eventDate.year,
              let month = reminder.eventDate.month,
              let day = reminder.eventDate.day
        else {
            return []
        }
        let key = CalendarDayComponents(year: year, month: month, day: day)
        return visibleDays.contains(key) ? [key] : []
    }

    /// Active reminders that belong on a selected calendar day.
    static func reminders(
        on day: CalendarDayComponents,
        from reminders: [Reminder],
        rangeStart: Date,
        engine: ReminderRuleEngine? = nil
    ) -> [Reminder] {
        let engine = engine ?? ReminderRuleEngine(policy: displayPolicy)
        return reminders.filter { reminder in
            indicatorDays(
                for: reminder,
                visibleDays: [day],
                rangeStart: rangeStart,
                engine: engine
            ).contains(day)
        }
        .sorted { lhs, rhs in
            (lhs.sortDate() ?? .distantFuture) < (rhs.sortDate() ?? .distantFuture)
        }
    }
}

/// Maps EventKit domain events onto calendar day keys using each event's timezone.
enum CalendarMonthEventIndexer {
    static func day(
        for event: CalendarEvent,
        displayCalendar: Calendar
    ) -> CalendarDayComponents? {
        var calendar = displayCalendar
        if let tz = TimeZone(identifier: event.timeZoneIdentifier) {
            calendar.timeZone = tz
        }
        return CalendarDayComponents.from(date: event.startDate, calendar: calendar)
    }

    static func indicatorDays(
        for events: [CalendarEvent],
        visibleDays: Set<CalendarDayComponents>,
        displayCalendar: Calendar
    ) -> Set<CalendarDayComponents> {
        var days = Set<CalendarDayComponents>()
        for event in events {
            guard let day = day(for: event, displayCalendar: displayCalendar),
                  visibleDays.contains(day)
            else { continue }
            days.insert(day)
        }
        return days
    }

    static func events(
        on day: CalendarDayComponents,
        from events: [CalendarEvent],
        displayCalendar: Calendar
    ) -> [CalendarEvent] {
        events.filter { event in
            Self.day(for: event, displayCalendar: displayCalendar) == day
        }
        .sorted { $0.startDate < $1.startDate }
    }
}

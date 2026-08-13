import Foundation

/// Pure, deterministic occurrence calculator.
/// Standing rules + optional snooze + Calendar/TimeZone → occurrences.
/// No SwiftUI. No UserNotifications. Not MainActor-bound.
struct ReminderRuleEngine: Sendable {
    var policy: ReminderSchedulingPolicy
    var calendar: Calendar

    init(
        policy: ReminderSchedulingPolicy = .default,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) {
        self.policy = policy
        self.calendar = calendar
    }

    /// Calculates occurrences for enabled standing rules, plus an active snooze if present.
    /// Snooze never suppresses standing future occurrences.
    func occurrences(
        for reminder: Reminder,
        now: Date = Date(),
        onlyFuture: Bool = true
    ) -> [ReminderOccurrence] {
        var calendar = calendar
        if let timeZone = TimeZone(identifier: reminder.timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }

        let standing = reminder.rules.filter { $0.enabled && $0.ruleType != .snoozeOneOff }
        let recurringRules = standing.filter { $0.ruleType == .recurring }
        let oneShotRules = standing.filter {
            $0.ruleType == .exactAtEvent || $0.ruleType == .beforeEvent
        }

        var results: [ReminderOccurrence] = []

        if recurringRules.isEmpty {
            guard let eventInstant = eventInstant(for: reminder, calendar: calendar) else {
                return appendSnooze(results, reminder: reminder, now: now, onlyFuture: onlyFuture)
            }
            for rule in oneShotRules {
                if let occurrence = makeOccurrence(
                    rule: rule,
                    eventInstant: eventInstant,
                    calendar: calendar,
                    now: now,
                    onlyFuture: onlyFuture
                ) {
                    results.append(occurrence)
                }
            }
        } else {
            // Recurring: generate anchors, fire recurring + before/exact relative to each anchor.
            for recurringRule in recurringRules {
                let anchors = recurrenceAnchors(
                    for: reminder,
                    rule: recurringRule,
                    calendar: calendar,
                    now: now
                )
                for anchor in anchors {
                    if let occurrence = makeOccurrence(
                        rule: recurringRule,
                        eventInstant: anchor,
                        calendar: calendar,
                        now: now,
                        onlyFuture: onlyFuture
                    ) {
                        results.append(occurrence)
                    }
                    for rule in oneShotRules {
                        if let occurrence = makeOccurrence(
                            rule: rule,
                            eventInstant: anchor,
                            calendar: calendar,
                            now: now,
                            onlyFuture: onlyFuture
                        ) {
                            results.append(occurrence)
                        }
                    }
                }
            }
        }

        results = appendSnooze(results, reminder: reminder, now: now, onlyFuture: onlyFuture)
        let deduped = deduplicate(results)
        if deduped.count <= policy.maxOccurrencesPerReminder {
            return deduped
        }
        return Array(deduped.prefix(policy.maxOccurrencesPerReminder))
    }

    /// Event instant used as the anchor for exact/before / recurrence wall-clock time.
    ///
    /// Date-only reminders use `policy.defaultTimeOfDay` (V1: 09:00) unless `eventTime` is set.
    func eventInstant(for reminder: Reminder, calendar: Calendar? = nil) -> Date? {
        var calendar = calendar ?? self.calendar
        if let timeZone = TimeZone(identifier: reminder.timeZoneIdentifier) {
            calendar.timeZone = timeZone
        }

        var components = Reminder.normalizedDate(reminder.eventDate)
        applyReminderTime(to: &components, reminder: reminder)
        return calendar.date(from: components)
    }

    func deduplicate(_ occurrences: [ReminderOccurrence]) -> [ReminderOccurrence] {
        var seenFireTimes = Set<TimeInterval>()
        var unique: [ReminderOccurrence] = []
        for occurrence in occurrences.sorted(by: { $0.fireAt < $1.fireAt }) {
            let key = occurrence.fireAt.timeIntervalSince1970
            if seenFireTimes.contains(key) { continue }
            seenFireTimes.insert(key)
            unique.append(occurrence)
        }
        return unique
    }

    static let snoozeRuleNamespace = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    // MARK: - Recurrence anchors

    /// Product policies (documented):
    /// - Monthly missing day (e.g. 31 Feb): **skip** that month.
    /// - Yearly Feb 29 on non-leap years: **skip** that year.
    /// - DST: calendar wall-clock arithmetic only (never fixed-second deltas).
    func recurrenceAnchors(
        for reminder: Reminder,
        rule: ReminderRule,
        calendar: Calendar,
        now: Date
    ) -> [Date] {
        guard let recurrence = rule.recurrence else { return [] }

        let horizonEnd = calendar.date(byAdding: .day, value: policy.horizonDays, to: now) ?? now
        let windowBounds = resolvedWindowBounds(rule.dateWindow, calendar: calendar)

        guard var cursorDay = startingSearchDay(
            reminder: reminder,
            windowStart: windowBounds?.start,
            calendar: calendar,
            now: now
        ) else {
            return []
        }

        var anchors: [Date] = []
        // Hard safety against runaway loops.
        var steps = 0
        let maxSteps = max(policy.horizonDays * 2, 800)

        while steps < maxSteps {
            steps += 1
            if cursorDay > horizonEnd { break }
            if let end = windowBounds?.end, cursorDay > end { break }

            if let windowStart = windowBounds?.start, cursorDay < windowStart {
                cursorDay = calendar.startOfDay(for: windowStart)
                continue
            }

            if matchesRecurrence(
                day: cursorDay,
                recurrence: recurrence,
                reminder: reminder,
                calendar: calendar
            ),
               let anchor = wallClockInstant(on: cursorDay, reminder: reminder, calendar: calendar),
               anchor > now {
                anchors.append(anchor)
                if anchors.count >= policy.maxOccurrencesPerReminder {
                    break
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: cursorDay) else { break }
            cursorDay = calendar.startOfDay(for: next)
        }

        return anchors.sorted()
    }

    // MARK: - Private

    private func applyReminderTime(to components: inout DateComponents, reminder: Reminder) {
        if let eventTime = reminder.eventTime,
           let hour = eventTime.hour,
           let minute = eventTime.minute {
            components.hour = hour
            components.minute = minute
            components.second = 0
        } else {
            components.hour = policy.defaultTimeOfDay.hour
            components.minute = policy.defaultTimeOfDay.minute
            components.second = 0
        }
    }

    private func wallClockInstant(on day: Date, reminder: Reminder, calendar: Calendar) -> Date? {
        var comps = calendar.dateComponents([.year, .month, .day], from: day)
        applyReminderTime(to: &comps, reminder: reminder)
        return calendar.date(from: comps)
    }

    private func makeOccurrence(
        rule: ReminderRule,
        eventInstant: Date,
        calendar: Calendar,
        now: Date,
        onlyFuture: Bool
    ) -> ReminderOccurrence? {
        guard let fireAt = fireDate(for: rule, eventInstant: eventInstant, calendar: calendar) else {
            return nil
        }
        if onlyFuture && fireAt <= now {
            return nil
        }
        return ReminderOccurrence(
            ruleID: rule.id,
            occurrenceKey: ReminderOccurrence.occurrenceKey(for: fireAt),
            fireAt: fireAt,
            ruleType: rule.ruleType,
            isSnooze: false
        )
    }

    private func appendSnooze(
        _ results: [ReminderOccurrence],
        reminder: Reminder,
        now: Date,
        onlyFuture: Bool
    ) -> [ReminderOccurrence] {
        var results = results
        if let snooze = reminder.snooze, snooze.isActive(relativeTo: now) {
            let fireAt = snooze.until
            if !onlyFuture || fireAt > now {
                results.append(
                    ReminderOccurrence(
                        ruleID: Self.snoozeRuleNamespace,
                        occurrenceKey: ReminderOccurrence.occurrenceKey(for: fireAt),
                        fireAt: fireAt,
                        ruleType: .snoozeOneOff,
                        isSnooze: true
                    )
                )
            }
        }
        return results
    }

    private func fireDate(
        for rule: ReminderRule,
        eventInstant: Date,
        calendar: Calendar
    ) -> Date? {
        switch rule.ruleType {
        case .exactAtEvent, .recurring:
            return eventInstant
        case .beforeEvent:
            guard let value = rule.offsetValue, let unit = rule.offsetUnit, value >= 0 else {
                return nil
            }
            return calendar.date(byAdding: component(for: unit), value: -value, to: eventInstant)
        case .snoozeOneOff, .dateWindow:
            return nil
        }
    }

    private func component(for unit: ReminderOffsetUnit) -> Calendar.Component {
        switch unit {
        case .minute: return .minute
        case .hour: return .hour
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    private func resolvedWindowBounds(
        _ window: ReminderDateWindow?,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        guard let window else { return nil }
        guard let start = calendar.date(from: DateComponents(
            year: window.startDate.year,
            month: window.startDate.month,
            day: window.startDate.day,
            hour: 0,
            minute: 0
        )),
        let endDay = calendar.date(from: DateComponents(
            year: window.endDate.year,
            month: window.endDate.month,
            day: window.endDate.day,
            hour: 0,
            minute: 0
        )),
        let end = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: endDay)
        else {
            return nil
        }
        return (calendar.startOfDay(for: start), end)
    }

    private func startingSearchDay(
        reminder: Reminder,
        windowStart: Date?,
        calendar: Calendar,
        now: Date
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        var start = today
        if let windowStart {
            start = max(start, calendar.startOfDay(for: windowStart))
        }
        // Look a few days back so weekly matching near `now` still finds the next weekday promptly.
        return calendar.date(byAdding: .day, value: -1, to: start).map { calendar.startOfDay(for: $0) }
    }

    private func matchesRecurrence(
        day: Date,
        recurrence: ReminderRecurrence,
        reminder: Reminder,
        calendar: Calendar
    ) -> Bool {
        let comps = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
        switch recurrence.frequency {
        case .daily:
            return matchesInterval(
                day: day,
                recurrence: recurrence,
                reminder: reminder,
                calendar: calendar,
                component: .day
            )
        case .weekly:
            let weekdays = recurrence.weekdays ?? {
                if let eventDay = calendar.date(from: Reminder.normalizedDate(reminder.eventDate)) {
                    return [calendar.component(.weekday, from: eventDay)]
                }
                return []
            }()
            guard let weekday = comps.weekday, weekdays.contains(weekday) else { return false }
            return true
        case .monthly:
            let targetDay = recurrence.dayOfMonth ?? reminder.eventDate.day ?? comps.day
            guard let targetDay, let dayValue = comps.day, dayValue == targetDay else {
                return false
            }
            // Skip months that don't contain this day (already impossible if dayValue matches).
            guard let year = comps.year, let month = comps.month else { return false }
            return isValidDay(year: year, month: month, day: targetDay, calendar: calendar)
        case .yearly:
            guard let month = reminder.eventDate.month,
                  let dayOfMonth = reminder.eventDate.day,
                  comps.month == month,
                  comps.day == dayOfMonth
            else {
                return false
            }
            guard let year = comps.year else { return false }
            // Leap-day policy: skip non-leap years when event is Feb 29.
            return isValidDay(year: year, month: month, day: dayOfMonth, calendar: calendar)
        }
    }

    private func matchesInterval(
        day: Date,
        recurrence: ReminderRecurrence,
        reminder: Reminder,
        calendar: Calendar,
        component: Calendar.Component
    ) -> Bool {
        guard recurrence.interval <= 1 else {
            // V1 UI uses interval 1; keep deterministic support for N.
            guard let origin = calendar.date(from: Reminder.normalizedDate(reminder.eventDate)) else {
                return true
            }
            let originStart = calendar.startOfDay(for: origin)
            let dayStart = calendar.startOfDay(for: day)
            let delta = calendar.dateComponents([component], from: originStart, to: dayStart)
            let value: Int
            switch component {
            case .day: value = delta.day ?? 0
            default: value = 0
            }
            return value >= 0 && value % recurrence.interval == 0
        }
        return true
    }

    private func isValidDay(year: Int, month: Int, day: Int, calendar: Calendar) -> Bool {
        var comps = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: comps) else { return false }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == year && back.month == month && back.day == day
    }
}

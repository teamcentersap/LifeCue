import Foundation

/// Year-month-day identity for calendar cells and indicators.
struct CalendarDayComponents: Hashable, Comparable, Sendable {
    let year: Int
    let month: Int
    let day: Int

    static func < (lhs: CalendarDayComponents, rhs: CalendarDayComponents) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    static func from(date: Date, calendar: Calendar) -> CalendarDayComponents? {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = comps.year, let month = comps.month, let day = comps.day else { return nil }
        return CalendarDayComponents(year: year, month: month, day: day)
    }

    func date(in calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

/// One cell in a month grid (may belong to adjacent months for padding).
struct MonthCalendarCell: Identifiable, Equatable, Sendable {
    var id: CalendarDayComponents { day }
    let day: CalendarDayComponents
    let dayNumber: Int
    let isInDisplayedMonth: Bool
    let isToday: Bool
}

/// Pure month-grid builder (Mon–Sun layout). Deterministic and testable.
enum MonthCalendarGridBuilder {
    /// Gregorian calendar with Monday as first weekday for a calm, consistent grid.
    static func makeCalendar(timeZone: TimeZone = .current) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2 // Monday
        calendar.timeZone = timeZone
        return calendar
    }

    static func monthTitle(year: Int, month: Int, calendar: Calendar, locale: Locale = Locale(identifier: "en_GB")) -> String {
        var comps = DateComponents(year: year, month: month, day: 1)
        guard let date = calendar.date(from: comps) else { return "\(month)/\(year)" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: date)
    }

    /// Short weekday headers starting Monday.
    static func weekdaySymbols(calendar: Calendar, locale: Locale = Locale(identifier: "en_GB")) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        // Calendar weekdaySymbols are Sunday-first; rotate so Monday is first.
        let sundayFirst = symbols
        guard sundayFirst.count == 7 else { return sundayFirst }
        return Array(sundayFirst[1...]) + [sundayFirst[0]]
    }

    static func cells(
        year: Int,
        month: Int,
        today: Date,
        calendar: Calendar
    ) -> [MonthCalendarCell] {
        guard let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let monthRange = calendar.range(of: .day, in: .month, for: monthStart)
        else {
            return []
        }

        let todayDay = CalendarDayComponents.from(date: today, calendar: calendar)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        // Convert Sunday=1…Saturday=7 to Monday-based offset 0…6
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7

        guard let gridStart = calendar.date(byAdding: .day, value: -leading, to: monthStart) else {
            return []
        }

        var result: [MonthCalendarCell] = []
        result.reserveCapacity(42)
        for offset in 0..<42 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart),
                  let day = CalendarDayComponents.from(date: date, calendar: calendar)
            else { continue }
            let inMonth = day.month == month && day.year == year
            result.append(
                MonthCalendarCell(
                    day: day,
                    dayNumber: day.day,
                    isInDisplayedMonth: inMonth,
                    isToday: day == todayDay
                )
            )
        }
        // Ensure we cover the month (monthRange used for clarity / future assertions).
        _ = monthRange
        return result
    }

    static func addMonths(year: Int, month: Int, value: Int, calendar: Calendar) -> (year: Int, month: Int) {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let shifted = calendar.date(byAdding: .month, value: value, to: start)
        else {
            return (year, month)
        }
        let comps = calendar.dateComponents([.year, .month], from: shifted)
        return (comps.year ?? year, comps.month ?? month)
    }

    /// Absolute range covering all grid cells for EventKit / occurrence queries.
    static func visibleDateRange(
        year: Int,
        month: Int,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        let cells = cells(year: year, month: month, today: Date(), calendar: calendar)
        guard let first = cells.first?.day.date(in: calendar),
              let lastDay = cells.last?.day.date(in: calendar),
              let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: lastDay)
        else {
            return nil
        }
        return (calendar.startOfDay(for: first), end)
    }
}

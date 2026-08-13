import Foundation

enum CalendarEventDisplayFormatter {
    static func dateString(for event: CalendarEvent) -> String {
        let tz = TimeZone(identifier: event.timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let comps = calendar.dateComponents([.year, .month, .day], from: event.startDate)
        guard let date = calendar.date(from: comps) else { return "" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = tz
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMMM yyyy"
        return f.string(from: date)
    }

    static func timeString(for event: CalendarEvent) -> String? {
        guard !event.isAllDay else { return nil }
        let tz = TimeZone(identifier: event.timeZoneIdentifier) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tz
        let comps = calendar.dateComponents([.hour, .minute], from: event.startDate)
        guard let h = comps.hour, let m = comps.minute else { return nil }

        var dc = DateComponents(year: comps.year, month: comps.month, day: comps.day)
        // Use a fixed date to format time without locale-dependent date shifts.
        dc.year = 2000
        dc.month = 1
        dc.day = 1
        dc.hour = h
        dc.minute = m
        dc.second = 0
        let date = calendar.date(from: dc) ?? event.startDate

        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = tz
        f.locale = Locale(identifier: "en_GB")
        f.timeStyle = .short
        f.dateStyle = .none
        return f.string(from: date)
    }

    static func subtitle(for event: CalendarEvent) -> String {
        if event.isAllDay {
            return "All day · \(dateString(for: event))"
        }
        let t = timeString(for: event) ?? ""
        return "\(dateString(for: event)) · \(t)"
    }
}


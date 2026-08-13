import Foundation

/// Selected-day list item for the month calendar.
enum CalendarDayItem: Identifiable, Equatable {
    case reminder(Reminder)
    case event(CalendarEvent)

    var id: String {
        switch self {
        case .reminder(let reminder):
            return "r:\(reminder.id.uuidString)"
        case .event(let event):
            return "e:\(event.id)"
        }
    }
}

@MainActor
final class CalendarMonthViewModel: ObservableObject {
    @Published private(set) var year: Int
    @Published private(set) var month: Int
    @Published var selectedDay: CalendarDayComponents?
    @Published private(set) var cells: [MonthCalendarCell] = []
    @Published private(set) var reminderIndicatorDays: Set<CalendarDayComponents> = []
    @Published private(set) var eventIndicatorDays: Set<CalendarDayComponents> = []
    @Published private(set) var selectedReminders: [Reminder] = []
    @Published private(set) var selectedEvents: [CalendarEvent] = []

    @Published private(set) var authorizationStatus: CalendarAuthorizationStatus = .notDetermined
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// True after user intentionally requests access from the Calendar tab.
    @Published private(set) var didRequestAccessThisSession = false

    private let calendarService: CalendarServing
    private let reminderService: ReminderService
    private let displayCalendar: Calendar
    private let ruleEngine: ReminderRuleEngine
    private let clock: () -> Date

    private var cachedReminders: [Reminder] = []
    private var cachedEvents: [CalendarEvent] = []

    init(
        calendarService: CalendarServing,
        reminderService: ReminderService,
        displayCalendar: Calendar = MonthCalendarGridBuilder.makeCalendar(),
        ruleEngine: ReminderRuleEngine? = nil,
        clock: @escaping () -> Date = { Date() }
    ) {
        self.calendarService = calendarService
        self.reminderService = reminderService
        self.displayCalendar = displayCalendar
        self.ruleEngine = ruleEngine ?? ReminderRuleEngine(
            policy: CalendarMonthReminderIndexer.displayPolicy,
            calendar: displayCalendar
        )
        self.clock = clock

        let today = clock()
        let comps = displayCalendar.dateComponents([.year, .month, .day], from: today)
        self.year = comps.year ?? 2026
        self.month = comps.month ?? 1
        if let day = CalendarDayComponents.from(date: today, calendar: displayCalendar) {
            self.selectedDay = day
        }
        rebuildGrid()
    }

    var monthTitle: String {
        MonthCalendarGridBuilder.monthTitle(year: year, month: month, calendar: displayCalendar)
    }

    var weekdaySymbols: [String] {
        MonthCalendarGridBuilder.weekdaySymbols(calendar: displayCalendar)
    }

    var selectedDayTitle: String {
        guard let selectedDay,
              let date = selectedDay.date(in: displayCalendar)
        else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = displayCalendar
        formatter.timeZone = displayCalendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.setLocalizedDateFormatFromTemplate("d MMMM")
        return formatter.string(from: date)
    }

    var isSelectedDayEmpty: Bool {
        selectedReminders.isEmpty && selectedEvents.isEmpty
    }

    func goToPreviousMonth() {
        let next = MonthCalendarGridBuilder.addMonths(
            year: year,
            month: month,
            value: -1,
            calendar: displayCalendar
        )
        year = next.year
        month = next.month
        rebuildGrid()
        Task { await reloadVisibleRange() }
    }

    func goToNextMonth() {
        let next = MonthCalendarGridBuilder.addMonths(
            year: year,
            month: month,
            value: 1,
            calendar: displayCalendar
        )
        year = next.year
        month = next.month
        rebuildGrid()
        Task { await reloadVisibleRange() }
    }

    func goToCurrentMonth() {
        let today = clock()
        let comps = displayCalendar.dateComponents([.year, .month, .day], from: today)
        year = comps.year ?? year
        month = comps.month ?? month
        if let day = CalendarDayComponents.from(date: today, calendar: displayCalendar) {
            selectedDay = day
        }
        rebuildGrid()
        Task { await reloadVisibleRange() }
    }

    func selectDay(_ day: CalendarDayComponents) {
        selectedDay = day
        refreshSelectedDayItems()
    }

    /// Loads authorization (without requesting) and visible-range data.
    func loadInitial() async {
        isLoading = true
        defer { isLoading = false }
        authorizationStatus = await calendarService.authorizationStatus()
        rebuildGrid()
        await reloadVisibleRange()
    }

    /// User-intent Calendar access request (same path as Sprint 9).
    func requestAccess() async {
        didRequestAccessThisSession = true
        isLoading = true
        defer { isLoading = false }
        authorizationStatus = await calendarService.requestFullAccessToEvents()
        await reloadVisibleRange()
    }

    func refreshOnBecomeActive() async {
        authorizationStatus = await calendarService.authorizationStatus()
        await reloadVisibleRange()
    }

    // MARK: - Private

    private func rebuildGrid() {
        cells = MonthCalendarGridBuilder.cells(
            year: year,
            month: month,
            today: clock(),
            calendar: displayCalendar
        )
    }

    private func reloadVisibleRange() async {
        errorMessage = nil
        loadReminders()
        if authorizationStatus == .fullAccess {
            await loadEvents()
        } else {
            cachedEvents = []
        }
        recomputeIndicators()
        refreshSelectedDayItems()
    }

    private func loadReminders() {
        do {
            cachedReminders = try reminderService.allReminders().filter { $0.status == .active }
        } catch {
            cachedReminders = []
            errorMessage = "Couldn't load reminders."
        }
    }

    private func loadEvents() async {
        guard let range = MonthCalendarGridBuilder.visibleDateRange(
            year: year,
            month: month,
            calendar: displayCalendar
        ) else {
            cachedEvents = []
            return
        }
        do {
            cachedEvents = try await calendarService.fetchEvents(
                from: range.start,
                to: range.end,
                calendarIdentifiers: nil
            )
        } catch {
            cachedEvents = []
            errorMessage = "Couldn't load calendar events."
        }
    }

    private func recomputeIndicators() {
        let visible = Set(cells.map(\.day))
        guard let range = MonthCalendarGridBuilder.visibleDateRange(
            year: year,
            month: month,
            calendar: displayCalendar
        ) else {
            reminderIndicatorDays = []
            eventIndicatorDays = []
            return
        }

        var reminderDays = Set<CalendarDayComponents>()
        for reminder in cachedReminders {
            reminderDays.formUnion(
                CalendarMonthReminderIndexer.indicatorDays(
                    for: reminder,
                    visibleDays: visible,
                    rangeStart: range.start,
                    engine: ruleEngine
                )
            )
        }
        reminderIndicatorDays = reminderDays
        eventIndicatorDays = CalendarMonthEventIndexer.indicatorDays(
            for: cachedEvents,
            visibleDays: visible,
            displayCalendar: displayCalendar
        )
    }

    private func refreshSelectedDayItems() {
        guard let selectedDay,
              let range = MonthCalendarGridBuilder.visibleDateRange(
                year: year,
                month: month,
                calendar: displayCalendar
              )
        else {
            selectedReminders = []
            selectedEvents = []
            return
        }
        selectedReminders = CalendarMonthReminderIndexer.reminders(
            on: selectedDay,
            from: cachedReminders,
            rangeStart: range.start,
            engine: ruleEngine
        )
        selectedEvents = CalendarMonthEventIndexer.events(
            on: selectedDay,
            from: cachedEvents,
            displayCalendar: displayCalendar
        )
    }
}

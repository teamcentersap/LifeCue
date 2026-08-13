import XCTest
@testable import LifeCue

@MainActor
final class CalendarMonthTests: XCTestCase {
    private var displayCalendar: Calendar!
    private var now: Date!
    private var personRepo: InMemoryPersonRepository!
    private var contextRepo: InMemoryContextRepository!
    private var reminderRepo: InMemoryReminderRepository!
    private var reminderService: ReminderService!
    private var personService: PersonService!
    private var contextService: ContextService!
    private var calendarService: FakeCalendarService!
    private var scheduler: FakeNotificationScheduler!

    override func setUp() {
        super.setUp()
        displayCalendar = MonthCalendarGridBuilder.makeCalendar(
            timeZone: TimeZone(identifier: "Asia/Kolkata")!
        )
        now = displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 12))!
        personRepo = InMemoryPersonRepository()
        contextRepo = InMemoryContextRepository()
        reminderRepo = InMemoryReminderRepository()
        scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        reminderService = ReminderService(
            repository: reminderRepo,
            notificationScheduler: scheduler,
            personRepository: personRepo,
            contextRepository: contextRepo,
            ruleEngine: ReminderRuleEngine(calendar: displayCalendar),
            calendar: displayCalendar,
            clock: { self.now }
        )
        personService = PersonService(repository: personRepo)
        contextService = ContextService(repository: contextRepo, personRepository: personRepo)
        calendarService = FakeCalendarService(status: .fullAccess, events: [])
    }

    private func makeVM(
        status: CalendarAuthorizationStatus = .fullAccess,
        events: [CalendarEvent] = []
    ) -> CalendarMonthViewModel {
        calendarService = FakeCalendarService(status: status, events: events)
        return CalendarMonthViewModel(
            calendarService: calendarService,
            reminderService: reminderService,
            displayCalendar: displayCalendar,
            ruleEngine: ReminderRuleEngine(
                policy: CalendarMonthReminderIndexer.displayPolicy,
                calendar: displayCalendar
            ),
            clock: { self.now }
        )
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> CalendarDayComponents {
        CalendarDayComponents(year: y, month: m, day: d)
    }

    // MARK: - Grid / navigation

    /// TC-CALENDAR-MONTH-001
    func testCurrentMonthGridContainsCorrectDates() {
        let cells = MonthCalendarGridBuilder.cells(
            year: 2026,
            month: 8,
            today: now,
            calendar: displayCalendar
        )
        XCTAssertEqual(cells.count, 42)
        let inMonth = cells.filter(\.isInDisplayedMonth)
        XCTAssertEqual(inMonth.count, 31)
        XCTAssertEqual(inMonth.first?.day, day(2026, 8, 1))
        XCTAssertEqual(inMonth.last?.day, day(2026, 8, 31))
        XCTAssertEqual(
            MonthCalendarGridBuilder.monthTitle(year: 2026, month: 8, calendar: displayCalendar),
            "August 2026"
        )
    }

    /// TC-CALENDAR-MONTH-002
    func testPreviousMonthNavigationWorks() async {
        let vm = makeVM()
        await vm.loadInitial()
        XCTAssertEqual(vm.month, 8)
        vm.goToPreviousMonth()
        XCTAssertEqual(vm.year, 2026)
        XCTAssertEqual(vm.month, 7)
        XCTAssertTrue(vm.cells.contains { $0.isInDisplayedMonth && $0.day == day(2026, 7, 1) })
    }

    /// TC-CALENDAR-MONTH-003
    func testNextMonthNavigationWorks() async {
        let vm = makeVM()
        await vm.loadInitial()
        vm.goToNextMonth()
        XCTAssertEqual(vm.month, 9)
        XCTAssertTrue(vm.cells.contains { $0.isInDisplayedMonth && $0.day == day(2026, 9, 1) })
    }

    /// TC-CALENDAR-MONTH-004
    func testTodayIsCorrectlyIdentified() {
        let cells = MonthCalendarGridBuilder.cells(
            year: 2026,
            month: 8,
            today: now,
            calendar: displayCalendar
        )
        let todayCells = cells.filter(\.isToday)
        XCTAssertEqual(todayCells.count, 1)
        XCTAssertEqual(todayCells.first?.day, day(2026, 8, 11))
    }

    // MARK: - Reminder indicators

    /// TC-CALENDAR-MONTH-005
    func testLifeCueReminderDateProducesReminderIndicator() async throws {
        _ = try await reminderService.create(
            title: "Doctor",
            eventDate: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 15))!,
            includeTime: true,
            eventTime: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 15, hour: 16))!,
            rules: [.exactAtEvent()]
        )
        let vm = makeVM()
        await vm.loadInitial()
        XCTAssertTrue(vm.reminderIndicatorDays.contains(day(2026, 8, 15)))
    }

    /// TC-CALENDAR-MONTH-006
    func testMultipleRemindersOnSameDateProduceOneDateIndicator() async throws {
        let eventDay = displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 20))!
        _ = try await reminderService.create(
            title: "A",
            eventDate: eventDay,
            includeTime: false,
            eventTime: nil,
            rules: [.exactAtEvent()]
        )
        _ = try await reminderService.create(
            title: "B",
            eventDate: eventDay,
            includeTime: true,
            eventTime: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 20, hour: 18))!,
            rules: [.exactAtEvent()]
        )
        let vm = makeVM()
        await vm.loadInitial()
        XCTAssertTrue(vm.reminderIndicatorDays.contains(day(2026, 8, 20)))
        // Set membership — one day key regardless of count.
        XCTAssertEqual(vm.reminderIndicatorDays.filter { $0 == day(2026, 8, 20) }.count, 1)
    }

    /// TC-CALENDAR-MONTH-007
    func testCompletedReminderDoesNotProduceActiveIndicator() async throws {
        let created = try await reminderService.create(
            title: "Done",
            eventDate: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 18))!,
            includeTime: false,
            eventTime: nil,
            rules: [.exactAtEvent()]
        )
        _ = try await reminderService.complete(id: created.reminder.id)
        let vm = makeVM()
        await vm.loadInitial()
        XCTAssertFalse(vm.reminderIndicatorDays.contains(day(2026, 8, 18)))
    }

    /// TC-CALENDAR-MONTH-008
    func testDeletedReminderDoesNotAppear() async throws {
        let created = try await reminderService.create(
            title: "Gone",
            eventDate: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 19))!,
            includeTime: false,
            eventTime: nil,
            rules: [.exactAtEvent()]
        )
        try await reminderService.delete(id: created.reminder.id)
        let vm = makeVM()
        await vm.loadInitial()
        XCTAssertFalse(vm.reminderIndicatorDays.contains(day(2026, 8, 19)))
        vm.selectDay(day(2026, 8, 19))
        XCTAssertTrue(vm.selectedReminders.isEmpty)
    }

    /// TC-CALENDAR-MONTH-009
    func testRecurringReminderAppearsOnValidOccurrenceDates() async throws {
        _ = try await reminderService.create(
            title: "Daily meds",
            eventDate: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11))!,
            includeTime: true,
            eventTime: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9))!,
            rules: [.recurring(.daily())]
        )
        let vm = makeVM()
        await vm.loadInitial()
        // From probe before month, daily occurrences should mark upcoming days in August.
        XCTAssertTrue(vm.reminderIndicatorDays.contains(day(2026, 8, 12)))
        XCTAssertTrue(vm.reminderIndicatorDays.contains(day(2026, 8, 13)))
    }

    /// TC-CALENDAR-MONTH-010
    func testDateWindowRestrictionsAreRespected() async throws {
        var windowed = ReminderRule.recurring(.daily())
        windowed.dateWindow = ReminderDateWindow(
            startDate: DateComponents(year: 2026, month: 8, day: 20),
            endDate: DateComponents(year: 2026, month: 8, day: 22)
        )
        _ = try await reminderService.create(
            title: "Windowed",
            eventDate: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11))!,
            includeTime: true,
            eventTime: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 11, hour: 9))!,
            rules: [windowed]
        )
        let vm = makeVM()
        await vm.loadInitial()
        XCTAssertFalse(vm.reminderIndicatorDays.contains(day(2026, 8, 15)))
        XCTAssertTrue(vm.reminderIndicatorDays.contains(day(2026, 8, 20)))
        XCTAssertTrue(vm.reminderIndicatorDays.contains(day(2026, 8, 21)))
        XCTAssertTrue(vm.reminderIndicatorDays.contains(day(2026, 8, 22)))
        XCTAssertFalse(vm.reminderIndicatorDays.contains(day(2026, 8, 23)))
    }

    // MARK: - EventKit indicators / selection

    /// TC-CALENDAR-MONTH-011
    func testEventKitEventDateProducesCalendarIndicator() async {
        let tz = displayCalendar.timeZone
        let start = displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 10))!
        let end = start.addingTimeInterval(3600)
        let event = CalendarEvent(
            id: "e1",
            title: "School meeting",
            startDate: start,
            endDate: end,
            isAllDay: false,
            calendarName: "Work",
            calendarIdentifier: "cal1",
            timeZoneIdentifier: tz.identifier
        )
        let vm = makeVM(events: [event])
        await vm.loadInitial()
        XCTAssertTrue(vm.eventIndicatorDays.contains(day(2026, 8, 14)))
    }

    /// TC-CALENDAR-MONTH-012
    func testSelectedDateShowsLifeCueReminders() async throws {
        _ = try await reminderService.create(
            title: "Doctor appointment",
            eventDate: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 16))!,
            includeTime: true,
            eventTime: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 16, hour: 16))!,
            rules: [.exactAtEvent()]
        )
        let vm = makeVM()
        await vm.loadInitial()
        vm.selectDay(day(2026, 8, 16))
        XCTAssertEqual(vm.selectedReminders.count, 1)
        XCTAssertEqual(vm.selectedReminders.first?.title, "Doctor appointment")
    }

    /// TC-CALENDAR-MONTH-013
    func testSelectedDateShowsEventKitEvents() async {
        let start = displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 17, hour: 10))!
        let event = CalendarEvent(
            id: "e2",
            title: "School meeting",
            startDate: start,
            endDate: start.addingTimeInterval(3600),
            isAllDay: false,
            calendarName: "Family",
            calendarIdentifier: "cal1",
            timeZoneIdentifier: displayCalendar.timeZone.identifier
        )
        let vm = makeVM(events: [event])
        await vm.loadInitial()
        vm.selectDay(day(2026, 8, 17))
        XCTAssertEqual(vm.selectedEvents.count, 1)
        XCTAssertEqual(vm.selectedEvents.first?.title, "School meeting")
    }

    /// TC-CALENDAR-MONTH-014
    func testEmptyDateShowsEmptyState() async {
        let vm = makeVM()
        await vm.loadInitial()
        vm.selectDay(day(2026, 8, 3))
        XCTAssertTrue(vm.isSelectedDayEmpty)
    }

    /// TC-CALENDAR-MONTH-015
    func testAllDayEventKitEventDisplaysWithoutInventedTime() {
        let start = displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 25, hour: 0))!
        let end = displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 0))!
        let event = CalendarEvent(
            id: "allday",
            title: "Holiday",
            startDate: start,
            endDate: end,
            isAllDay: true,
            calendarName: "Personal",
            calendarIdentifier: "cal1",
            timeZoneIdentifier: displayCalendar.timeZone.identifier
        )
        XCTAssertNil(CalendarEventDisplayFormatter.timeString(for: event))
        XCTAssertTrue(CalendarEventDisplayFormatter.subtitle(for: event).contains("All day"))
    }

    /// TC-CALENDAR-MONTH-016
    func testReminderStoredTimezoneRemainsAuthoritative() async throws {
        let tokyoID = "Asia/Tokyo"
        let created = try await reminderService.create(
            title: "Tokyo reminder",
            eventDate: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 21))!,
            includeTime: true,
            eventTime: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 21, hour: 9, minute: 0))!,
            rules: [.exactAtEvent()],
            timeZoneIdentifier: tokyoID
        )
        XCTAssertEqual(created.reminder.timeZoneIdentifier, tokyoID)
        XCTAssertEqual(created.reminder.eventDate.day, 21)
        XCTAssertEqual(created.reminder.eventDate.month, 8)

        let days = CalendarMonthReminderIndexer.indicatorDays(
            for: created.reminder,
            visibleDays: Set(MonthCalendarGridBuilder.cells(
                year: 2026, month: 8, today: now, calendar: displayCalendar
            ).map(\.day)),
            rangeStart: displayCalendar.date(from: DateComponents(year: 2026, month: 7, day: 27))!,
            engine: ReminderRuleEngine(
                policy: CalendarMonthReminderIndexer.displayPolicy,
                calendar: displayCalendar
            )
        )
        XCTAssertTrue(days.contains(day(2026, 8, 21)))
        // Display formatters must keep using the reminder's stored zone.
        XCTAssertEqual(
            created.reminder.calendarInStoredTimeZone().timeZone.identifier,
            tokyoID
        )
    }

    /// TC-CALENDAR-MONTH-017
    func testEventKitPermissionIsNotRequestedAtAppLaunch() async {
        let vm = makeVM(status: .notDetermined)
        await vm.loadInitial()
        XCTAssertEqual(calendarService.requestAccessCallCount, 0)
        XCTAssertEqual(vm.authorizationStatus, .notDetermined)
        XCTAssertFalse(vm.didRequestAccessThisSession)
    }

    /// TC-CALENDAR-MONTH-018
    func testDeniedCalendarPermissionShowsExistingRecoveryPath() async {
        let vm = makeVM(status: .denied)
        await vm.loadInitial()
        XCTAssertEqual(vm.authorizationStatus, .denied)
        // Recovery UI is driven by this status (Open Settings) — same Sprint 9 path.
        XCTAssertEqual(calendarService.requestAccessCallCount, 0)
    }

    /// TC-CALENDAR-MONTH-019
    func testPersonContextMetadataResolvesInSelectedDateReminder() async throws {
        let person = try personService.create(name: "Child 1")
        let context = try contextService.create(name: "Doctor", personID: person.id)
        _ = try await reminderService.create(
            title: "Doctor appointment",
            eventDate: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 28))!,
            includeTime: true,
            eventTime: displayCalendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 16))!,
            rules: [.exactAtEvent()],
            personID: person.id,
            contextID: context.id
        )
        let vm = makeVM()
        await vm.loadInitial()
        vm.selectDay(day(2026, 8, 28))
        let reminder = try XCTUnwrap(vm.selectedReminders.first)
        let resolver = ReminderMetadataResolver(
            personService: personService,
            contextService: contextService
        )
        XCTAssertEqual(resolver.compactSubtitle(for: reminder), "Child 1 · Doctor")
    }

    /// TC-CALENDAR-MONTH-020
    func testReminderTapOpensExistingReminderDetailView() {
        XCTAssertEqual(CalendarMonthReminderNavigation.detailDestinationName, "ReminderDetailView")
        XCTAssertTrue(CalendarMonthReminderNavigation.opensExistingReminderDetail)
    }
}

import XCTest
@testable import LifeCue

final class ReminderRecurrenceEngineTests: XCTestCase {
    private var calendar: Calendar!
    private var timeZone: TimeZone!
    private var engine: ReminderRuleEngine!
    private var now: Date!

    override func setUp() {
        super.setUp()
        timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        engine = ReminderRuleEngine(calendar: calendar)
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8, minute: 0))!
    }

    private func reminder(
        month: Int = 8,
        day: Int = 10,
        year: Int = 2026,
        hour: Int? = 9,
        minute: Int? = 0,
        rules: [ReminderRule],
        timeZoneIdentifier: String? = nil
    ) -> Reminder {
        Reminder(
            title: "Test",
            eventDate: DateComponents(year: year, month: month, day: day),
            eventTime: hour.map { DateComponents(hour: $0, minute: minute ?? 0) },
            timeZoneIdentifier: timeZoneIdentifier ?? timeZone.identifier,
            rules: rules
        )
    }

    private func days(_ dates: [Date]) -> [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return dates.map { formatter.string(from: $0) }
    }

    /// TC-RULE-REC-001
    func testDailyRecurrence() {
        let occ = engine.occurrences(for: reminder(rules: [.recurring(.daily())]), now: now)
        XCTAssertEqual(days(Array(occ.prefix(3).map(\.fireAt))), [
            "2026-08-10", "2026-08-11", "2026-08-12"
        ])
    }

    /// TC-RULE-REC-002
    func testWeeklyRecurrence() {
        let occ = engine.occurrences(
            for: reminder(rules: [.recurring(.weekly(weekdays: [2]))]),
            now: now
        )
        XCTAssertEqual(days(Array(occ.prefix(4).map(\.fireAt))), [
            "2026-08-10", "2026-08-17", "2026-08-24", "2026-08-31"
        ])
    }

    /// TC-RULE-REC-003
    func testMultipleWeekdays() {
        let occ = engine.occurrences(
            for: reminder(rules: [.recurring(.weekly(weekdays: [2, 4]))]),
            now: now
        )
        XCTAssertEqual(days(Array(occ.prefix(4).map(\.fireAt))), [
            "2026-08-10", "2026-08-12", "2026-08-17", "2026-08-19"
        ])
    }

    /// TC-RULE-REC-004
    func testMonthlyRecurrence() {
        let occ = engine.occurrences(
            for: reminder(day: 15, rules: [.recurring(.monthly(dayOfMonth: 15))]),
            now: now
        )
        XCTAssertEqual(days(Array(occ.prefix(3).map(\.fireAt))), [
            "2026-08-15", "2026-09-15", "2026-10-15"
        ])
    }

    /// TC-RULE-REC-005
    func testMonthly31stSkipsInvalidMonths() {
        let rem = reminder(month: 1, day: 31, year: 2026, rules: [.recurring(.monthly(dayOfMonth: 31))])
        let janNow = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 8))!
        let list = days(engine.occurrences(for: rem, now: janNow).prefix(4).map(\.fireAt))
        XCTAssertTrue(list.contains("2026-01-31"))
        XCTAssertFalse(list.contains(where: { $0.hasPrefix("2026-02") }))
        XCTAssertTrue(list.contains("2026-03-31"))
    }

    /// TC-RULE-REC-006
    func testYearlyRecurrence() {
        let occ = engine.occurrences(
            for: reminder(month: 9, day: 15, year: 2026, rules: [.recurring(.yearly())]),
            now: now
        )
        XCTAssertEqual(days(Array(occ.prefix(2).map(\.fireAt))), [
            "2026-09-15", "2027-09-15"
        ])
    }

    /// TC-RULE-REC-007
    func testLeapDayYearlySkipsNonLeapYears() {
        let rem = reminder(month: 2, day: 29, year: 2024, rules: [.recurring(.yearly())])
        let start = calendar.date(from: DateComponents(year: 2027, month: 6, day: 1, hour: 8))!
        let list = days(engine.occurrences(for: rem, now: start).map(\.fireAt))
        XCTAssertFalse(list.contains("2027-02-28"))
        XCTAssertFalse(list.contains("2027-02-29"))
        XCTAssertTrue(list.contains("2028-02-29"))
    }

    /// TC-RULE-REC-008
    func testCustomReminderTime() {
        let first = engine.occurrences(
            for: reminder(hour: 8, minute: 30, rules: [.recurring(.daily())]),
            now: now
        )[0].fireAt
        XCTAssertEqual(calendar.component(.hour, from: first), 8)
        XCTAssertEqual(calendar.component(.minute, from: first), 30)
    }

    /// TC-RULE-REC-009
    func testDateOnlyDefaultNineAM() {
        let rem = Reminder(
            title: "T",
            eventDate: DateComponents(year: 2026, month: 8, day: 20),
            eventTime: nil,
            timeZoneIdentifier: timeZone.identifier,
            rules: [.exactAtEvent()]
        )
        let fire = engine.occurrences(for: rem, now: now)[0].fireAt
        XCTAssertEqual(calendar.component(.hour, from: fire), 9)
        XCTAssertEqual(calendar.component(.minute, from: fire), 0)
    }

    /// TC-RULE-REC-010
    func testMultipleBeforeOffsets() {
        let rem = Reminder(
            title: "T",
            eventDate: DateComponents(year: 2026, month: 11, day: 30),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: timeZone.identifier,
            rules: [
                .beforeEvent(value: 14, unit: .day),
                .beforeEvent(value: 3, unit: .day),
                .beforeEvent(value: 1, unit: .day)
            ]
        )
        XCTAssertEqual(engine.occurrences(for: rem, now: now).count, 3)
    }

    /// TC-RULE-REC-011
    func testWeeksBeforeOffset() {
        let rem = Reminder(
            title: "T",
            eventDate: DateComponents(year: 2026, month: 8, day: 25),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: timeZone.identifier,
            rules: [.beforeEvent(value: 2, unit: .week)]
        )
        XCTAssertEqual(days(engine.occurrences(for: rem, now: now).map(\.fireAt)), ["2026-08-11"])
    }

    /// TC-RULE-REC-012…014
    func testDateWindowBounds() {
        let window = ReminderDateWindow(
            startDate: DateComponents(year: 2026, month: 9, day: 1),
            endDate: DateComponents(year: 2026, month: 9, day: 30)
        )
        let occ = engine.occurrences(
            for: reminder(month: 9, day: 1, rules: [.recurring(.weekly(weekdays: [2]), window: window)]),
            now: now
        )
        let list = days(occ.map(\.fireAt))
        XCTAssertEqual(list.first, "2026-09-07")
        XCTAssertEqual(list.last, "2026-09-28")
        XCTAssertFalse(list.contains("2026-10-05"))
    }

    /// TC-RULE-REC-015
    func testInvalidDateWindow() {
        let window = ReminderDateWindow(
            startDate: DateComponents(year: 2026, month: 9, day: 30),
            endDate: DateComponents(year: 2026, month: 9, day: 1)
        )
        XCTAssertThrowsError(try ReminderRuleValidator.validate(window: window, calendar: calendar))
    }

    /// TC-RULE-REC-016
    func testSameDayWindow() throws {
        let window = ReminderDateWindow(
            startDate: DateComponents(year: 2026, month: 8, day: 10),
            endDate: DateComponents(year: 2026, month: 8, day: 10)
        )
        try ReminderRuleValidator.validate(window: window, calendar: calendar)
        let list = days(
            engine.occurrences(
                for: reminder(rules: [.recurring(.daily(), window: window)]),
                now: now
            ).map(\.fireAt)
        )
        XCTAssertEqual(list, ["2026-08-10"])
    }

    /// TC-RULE-REC-017
    func testDeduplication() {
        let rem = Reminder(
            title: "T",
            eventDate: DateComponents(year: 2026, month: 8, day: 20),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: timeZone.identifier,
            rules: [.exactAtEvent(), .beforeEvent(value: 0, unit: .minute)]
        )
        XCTAssertEqual(engine.occurrences(for: rem, now: now).count, 1)
    }

    /// TC-RULE-REC-018
    func testStableOccurrenceIdentity() {
        let rem = reminder(rules: [.recurring(.daily())])
        let a = engine.occurrences(for: rem, now: now)
        let b = engine.occurrences(for: rem, now: now)
        XCTAssertEqual(a.map(\.identity), b.map(\.identity))
        XCTAssertEqual(Set(a.map(\.identity)).count, a.count)
    }

    /// TC-RULE-REC-023
    func testTimezoneWallClock() {
        let ny = TimeZone(identifier: "America/New_York")!
        var nyCal = Calendar(identifier: .gregorian)
        nyCal.timeZone = ny
        let nyEngine = ReminderRuleEngine(calendar: nyCal)
        let rem = reminder(
            hour: 9,
            minute: 0,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: "America/New_York"
        )
        let nyNow = nyCal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 7))!
        let fire = nyEngine.occurrences(for: rem, now: nyNow)[0].fireAt
        XCTAssertEqual(nyCal.component(.hour, from: fire), 9)
    }

    /// TC-RULE-REC-024
    func testDSTWallClock() {
        let ny = TimeZone(identifier: "America/New_York")!
        var nyCal = Calendar(identifier: .gregorian)
        nyCal.timeZone = ny
        let nyEngine = ReminderRuleEngine(calendar: nyCal)
        let rem = Reminder(
            title: "T",
            eventDate: DateComponents(year: 2026, month: 3, day: 7),
            eventTime: DateComponents(hour: 9, minute: 0),
            timeZoneIdentifier: "America/New_York",
            rules: [.recurring(.daily())]
        )
        let start = nyCal.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 8))!
        let around = nyEngine.occurrences(for: rem, now: start).filter {
            let day = nyCal.component(.day, from: $0.fireAt)
            return nyCal.component(.month, from: $0.fireAt) == 3 && (7...9).contains(day)
        }
        for item in around {
            XCTAssertEqual(nyCal.component(.hour, from: item.fireAt), 9)
        }
    }

    /// TC-RULE-REC-030
    func testSchedulingHorizonCapsOccurrences() {
        let occ = engine.occurrences(for: reminder(rules: [.recurring(.daily())]), now: now)
        XCTAssertLessThanOrEqual(occ.count, ReminderSchedulingPolicy.default.maxOccurrencesPerReminder)
    }

    /// TC-RULE-REC-028
    func testSnoozeDoesNotModifyStandingRecurrence() {
        var rem = reminder(rules: [.recurring(.daily())])
        let before = rem.rules
        rem.snooze = ReminderSnoozeState(until: now.addingTimeInterval(1800)) // 08:30, distinct from 09:00 fires
        let occ = engine.occurrences(for: rem, now: now)
        XCTAssertEqual(rem.rules, before)
        XCTAssertTrue(occ.contains(where: \.isSnooze))
        XCTAssertTrue(occ.contains(where: { $0.ruleType == .recurring }))
    }

    /// TC-RULE-REC-029
    func testRecurringPlusBeforeOffsets() {
        let occ = engine.occurrences(
            for: reminder(rules: [
                .recurring(.weekly(weekdays: [2])),
                .beforeEvent(value: 1, unit: .day)
            ]),
            now: now
        )
        XCTAssertGreaterThanOrEqual(occ.count, 2)
        XCTAssertTrue(occ.contains { $0.ruleType == .recurring })
        XCTAssertTrue(occ.contains { $0.ruleType == .beforeEvent })
    }

    /// TC-RULE-REC-025
    func testMonthEndSkipPolicy() {
        let feb = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 8))!
        let anchors = engine.recurrenceAnchors(
            for: reminder(month: 1, day: 31, year: 2026, rules: [.recurring(.monthly(dayOfMonth: 31))]),
            rule: .recurring(.monthly(dayOfMonth: 31)),
            calendar: calendar,
            now: feb
        )
        XCTAssertFalse(anchors.contains { calendar.component(.month, from: $0) == 2 })
    }
}

@MainActor
final class ReminderRecurrenceLifecycleTests: XCTestCase {
    private var calendar: Calendar!
    private var timeZone: TimeZone!
    private var now: Date!

    override func setUp() {
        super.setUp()
        timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 8))!
    }

    private func makeService(
        scheduler: FakeNotificationScheduler? = nil
    ) -> (ReminderService, InMemoryReminderRepository, FakeNotificationScheduler) {
        let notifications = scheduler ?? FakeNotificationScheduler()
        notifications.status = .authorized
        let repo = InMemoryReminderRepository()
        let service = ReminderService(
            repository: repo,
            notificationScheduler: notifications,
            ruleEngine: ReminderRuleEngine(calendar: calendar),
            calendar: calendar,
            clock: { self.now }
        )
        return (service, repo, notifications)
    }

    /// TC-RULE-REC-019
    func testEditRecurringReminderReschedules() async throws {
        let (service, repo, scheduler) = makeService()
        let created = try await service.create(
            title: "Weekly",
            eventDate: now,
            includeTime: true,
            eventTime: now,
            note: nil,
            rules: [.recurring(.weekly(weekdays: [2]))],
            timeZoneIdentifier: timeZone.identifier
        )
        XCTAssertFalse(scheduler.scheduled.isEmpty)
        var updated = created.reminder
        updated.rules = [.recurring(.weekly(weekdays: [4]))]
        _ = try await service.update(updated)
        XCTAssertEqual(try repo.fetchAll().count, 1)
        XCTAssertFalse(scheduler.scheduled.isEmpty)
    }

    /// TC-RULE-REC-020
    func testDeleteRecurringCancelsNotifications() async throws {
        let (service, _, scheduler) = makeService()
        let created = try await service.create(
            title: "Daily",
            eventDate: now,
            includeTime: true,
            eventTime: now,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        try await service.delete(id: created.reminder.id)
        XCTAssertTrue(scheduler.scheduled.filter { $0.identifier.contains(created.reminder.id.uuidString) }.isEmpty)
    }

    /// TC-RULE-REC-021
    func testCompleteRecurringCancelsFuture() async throws {
        let (service, _, scheduler) = makeService()
        let created = try await service.create(
            title: "Daily",
            eventDate: now,
            includeTime: true,
            eventTime: now,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        _ = try await service.complete(id: created.reminder.id)
        XCTAssertTrue(scheduler.scheduled.filter { $0.identifier.contains(created.reminder.id.uuidString) }.isEmpty)
    }

    /// TC-RULE-REC-022
    func testDisabledRecurringRuleSchedulesNothing() async throws {
        let (service, _, scheduler) = makeService()
        var rule = ReminderRule.recurring(.daily())
        rule.enabled = false
        _ = try await service.create(
            title: "Off",
            eventDate: now,
            includeTime: true,
            eventTime: now,
            note: nil,
            rules: [rule],
            timeZoneIdentifier: timeZone.identifier
        )
        XCTAssertTrue(scheduler.scheduled.isEmpty)
    }

    func testInFlightRecurringScheduleThenComplete() async throws {
        let base = FakeNotificationScheduler()
        base.status = .authorized
        let delayed = DelayedNotificationScheduler(backing: base)
        delayed.shouldPauseSchedules = false
        let repo = InMemoryReminderRepository()
        let service = ReminderService(
            repository: repo,
            notificationScheduler: delayed,
            ruleEngine: ReminderRuleEngine(calendar: calendar),
            calendar: calendar,
            clock: { self.now }
        )
        let created = try await service.create(
            title: "Race",
            eventDate: now,
            includeTime: true,
            eventTime: now,
            note: nil,
            rules: [.recurring(.daily())],
            timeZoneIdentifier: timeZone.identifier
        )
        delayed.shouldPauseSchedules = true
        var edited = created.reminder
        edited.title = "Race2"
        let updateTask = Task { try await service.update(edited) }
        let paused = await delayed.waitUntilPaused()
        XCTAssertTrue(paused)
        _ = try await service.complete(id: created.reminder.id)
        delayed.releasePausedSchedules()
        _ = try? await updateTask.value
        XCTAssertTrue(base.scheduled.filter { $0.identifier.contains(created.reminder.id.uuidString) }.isEmpty)
    }
}

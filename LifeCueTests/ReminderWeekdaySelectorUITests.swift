import XCTest
@testable import LifeCue

@MainActor
final class ReminderWeekdaySelectorUITests: XCTestCase {

    /// TC-DAY-UI-001 All seven weekdays are represented.
    func testAllSevenWeekdaysAreRepresented() {
        let weekdays = ReminderWeekdaySelectorUI.choices.map(\.weekday)
        XCTAssertEqual(Set(weekdays), Set(1...7))
        XCTAssertEqual(ReminderWeekdaySelectorUI.choices.count, 7)
        XCTAssertEqual(
            ReminderWeekdaySelectorUI.choices.map(\.label),
            ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        )
        // Labels are single-token abbreviations — never multi-line fragments.
        for choice in ReminderWeekdaySelectorUI.choices {
            XCTAssertFalse(choice.label.contains("\n"))
            XCTAssertEqual(choice.label.count, 3)
        }
    }

    /// TC-DAY-UI-002 Multiple weekday selection remains supported.
    func testMultipleWeekdaySelectionRemainsSupported() {
        var selected: Set<Int> = [2]
        ReminderWeekdaySelectorUI.toggle(weekday: 4, in: &selected)
        ReminderWeekdaySelectorUI.toggle(weekday: 6, in: &selected)
        XCTAssertEqual(selected, [2, 4, 6])
    }

    /// TC-DAY-UI-003 Monday + Wednesday + Friday selection is preserved.
    func testMondayWednesdayFridaySelection() throws {
        var selected: Set<Int> = [2]
        ReminderWeekdaySelectorUI.toggle(weekday: 4, in: &selected)
        ReminderWeekdaySelectorUI.toggle(weekday: 6, in: &selected)
        XCTAssertEqual(selected.sorted(), [2, 4, 6])

        let model = ReminderScheduleFormModel()
        model.repeatMode = .weekly
        model.selectedWeekdays = selected
        let rules = try model.buildRules(
            eventDate: DateComponents(year: 2026, month: 8, day: 10),
            calendar: Calendar(identifier: .gregorian)
        )
        let recurrence = rules.first(where: { $0.ruleType == .recurring })?.recurrence
        XCTAssertEqual(Set(recurrence?.weekdays ?? []), [2, 4, 6])
    }

    /// TC-DAY-UI-004 Existing saved weekday selections load unchanged.
    func testExistingSavedWeekdaysLoadUnchanged() throws {
        let reminder = try ReminderFactory.make(
            title: "Weekly class",
            eventDate: DateComponents(year: 2026, month: 8, day: 10),
            eventTime: DateComponents(hour: 9, minute: 0),
            rules: [.recurring(.weekly(weekdays: [2, 4, 6]))]
        )
        let model = ReminderScheduleFormModel()
        model.load(from: reminder, calendar: Calendar(identifier: .gregorian))
        XCTAssertEqual(model.repeatMode, .weekly)
        XCTAssertEqual(model.selectedWeekdays, [2, 4, 6])
    }

    /// TC-DAY-UI-005 Saving without changing weekdays preserves the same recurrence rule.
    func testSavingWithoutChangingWeekdaysPreservesRecurrence() throws {
        let calendar = Calendar(identifier: .gregorian)
        let reminder = try ReminderFactory.make(
            title: "Weekly class",
            eventDate: DateComponents(year: 2026, month: 8, day: 10),
            eventTime: DateComponents(hour: 9, minute: 0),
            rules: [.recurring(.weekly(weekdays: [2, 4, 6]))]
        )
        let model = ReminderScheduleFormModel()
        model.load(from: reminder, calendar: calendar)
        let rules = try model.buildRules(eventDate: reminder.eventDate, calendar: calendar)
        let recurrence = try XCTUnwrap(rules.first(where: { $0.ruleType == .recurring })?.recurrence)
        XCTAssertEqual(recurrence.frequency, .weekly)
        XCTAssertEqual(Set(recurrence.weekdays ?? []), [2, 4, 6])
    }

    /// TC-DAY-UI-006 Changing weekday selection updates only the intended weekdays.
    func testChangingWeekdaySelectionUpdatesOnlyIntendedDays() {
        var selected: Set<Int> = [2, 4, 6]
        ReminderWeekdaySelectorUI.toggle(weekday: 3, in: &selected)
        XCTAssertEqual(selected.sorted(), [2, 3, 4, 6])
        ReminderWeekdaySelectorUI.toggle(weekday: 4, in: &selected)
        XCTAssertEqual(selected.sorted(), [2, 3, 6])
        // Cannot clear the last remaining day.
        selected = [2]
        ReminderWeekdaySelectorUI.toggle(weekday: 2, in: &selected)
        XCTAssertEqual(selected, [2])
    }
}

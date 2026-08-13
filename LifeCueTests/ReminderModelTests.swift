import XCTest
@testable import LifeCue

final class ReminderModelTests: XCTestCase {
    func testFactoryRejectsEmptyTitle() {
        XCTAssertThrowsError(
            try ReminderFactory.make(
                title: "   ",
                eventDate: DateComponents(year: 2026, month: 8, day: 10)
            )
        ) { error in
            XCTAssertEqual(error as? ReminderValidationError, .emptyTitle)
        }
    }

    func testFactoryTrimsTitleAndNote() throws {
        let reminder = try ReminderFactory.make(
            title: "  Doctor appointment  ",
            eventDate: DateComponents(year: 2026, month: 9, day: 18),
            eventTime: DateComponents(hour: 16, minute: 0),
            note: "  Take reports.  "
        )

        XCTAssertEqual(reminder.title, "Doctor appointment")
        XCTAssertEqual(reminder.note, "Take reports.")
        XCTAssertEqual(reminder.status, .active)
        XCTAssertNil(reminder.completedAt)
    }

    func testBlankNoteBecomesNil() throws {
        let reminder = try ReminderFactory.make(
            title: "Call Rahul",
            eventDate: DateComponents(year: 2026, month: 8, day: 11),
            note: "   "
        )
        XCTAssertNil(reminder.note)
        XCTAssertFalse(reminder.hasNote)
    }

    func testFactoryRequiresCompleteDate() {
        XCTAssertThrowsError(
            try ReminderFactory.make(
                title: "Missing day",
                eventDate: DateComponents(year: 2026, month: 8)
            )
        ) { error in
            XCTAssertEqual(error as? ReminderValidationError, .missingEventDate)
        }
    }
}

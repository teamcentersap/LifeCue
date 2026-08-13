import XCTest
@testable import LifeCue

final class ReminderSprint15HelpTests: XCTestCase {
    private func question(id: String) -> HelpQuestion? {
        HelpContent.allQuestions.first { $0.id == id }
    }

    private func section(id: String) -> HelpSection? {
        HelpContent.sections.first { $0.id == id }
    }

    func testTC_HELP_001_helpContentExists() {
        XCTAssertFalse(HelpContent.sections.isEmpty)
    }

    func testTC_HELP_002_gettingStartedSectionExists() {
        XCTAssertNotNil(section(id: "getting-started"))
    }

    func testTC_HELP_003_creatingReminderSectionExists() {
        XCTAssertNotNil(section(id: "creating-reminder"))
    }

    func testTC_HELP_004_titleExplanationRemoved() {
        XCTAssertNil(question(id: "cr-title"))
    }

    func testTC_HELP_005_dateExplanationRemoved() {
        XCTAssertNil(question(id: "cr-date"))
    }

    func testTC_HELP_006_timeExplanationRemoved() {
        XCTAssertNil(question(id: "cr-time"))
    }

    func testTC_HELP_007_dateOnlyDefaultTimeExplanationExists() {
        let item = question(id: "cr-no-time")
        XCTAssertNotNil(item)
        XCTAssertTrue(item?.answer.localizedCaseInsensitiveContains("default reminder time") == true)
    }

    func testTC_HELP_008_repeatExplanationExists() {
        XCTAssertNotNil(question(id: "cr-repeat"))
    }

    func testTC_HELP_009_multipleWeekdayExplanationRemoved() {
        XCTAssertNil(question(id: "cr-weekdays"))
    }

    func testTC_HELP_010_limitDatesExplanationExists() {
        XCTAssertNotNil(question(id: "cr-limit-dates"))
    }

    func testTC_HELP_011_forExplanationExists() {
        XCTAssertNotNil(question(id: "cr-for"))
    }

    func testTC_HELP_012_contextExplanationExists() {
        XCTAssertNotNil(question(id: "cr-context"))
    }

    func testTC_HELP_013_calendarPrefillExplanationExists() {
        let item = question(id: "cr-calendar-prefill")
        XCTAssertNotNil(item)
        XCTAssertTrue(item?.answer.contains("prefill") == true)
    }

    func testTC_HELP_014_noteExplanationRemoved() {
        XCTAssertNil(question(id: "cr-note"))
    }

    func testTC_HELP_015_reviewExplanationExists() {
        XCTAssertNotNil(question(id: "cr-review"))
    }

    func testTC_HELP_016_backupExplanationExists() {
        XCTAssertNotNil(question(id: "bk-file"))
    }

    func testTC_HELP_017_backupReminderAutoExplanationExists() {
        XCTAssertNotNil(question(id: "bk-reminder-auto"))
    }

    func testHelpSectionsMatchExpectedTitles() {
        let titles = HelpContent.sections.map(\.title)
        XCTAssertTrue(titles.contains("Getting Started"))
        XCTAssertTrue(titles.contains("Creating a Reminder"))
        XCTAssertTrue(titles.contains("Notifications"))
        XCTAssertTrue(titles.contains("People & Contexts"))
        XCTAssertTrue(titles.contains("Calendar"))
        XCTAssertTrue(titles.contains("Image Extraction"))
        XCTAssertTrue(titles.contains("Backup & Restore"))
        XCTAssertTrue(titles.contains("Forwarding"))
    }
}

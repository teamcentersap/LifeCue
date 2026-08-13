import XCTest
@testable import LifeCue

final class ReminderRuleCodingTests: XCTestCase {
    func testCurrentVersionRoundTrip() throws {
        let rules = [
            ReminderRule.beforeEvent(value: 1, unit: .day),
            ReminderRule.exactAtEvent()
        ]
        let snooze = ReminderSnoozeState(until: Date(timeIntervalSince1970: 1_800_000_000))
        let data = try ReminderRuleCoding.encode(rules: rules, snooze: snooze)
        let payload = try ReminderRuleCoding.decode(data)
        XCTAssertEqual(payload.schemaVersion, ReminderRulesPayload.currentSchemaVersion)
        XCTAssertEqual(payload.rules.count, 2)
        XCTAssertEqual(payload.snooze, snooze)
    }

    func testLegacyBareArrayIsAcceptedAsV1() throws {
        let rules = [ReminderRule.beforeEvent(value: 1, unit: .week)]
        let legacy = try JSONEncoder().encode(rules)
        let payload = try ReminderRuleCoding.decode(legacy)
        // Normalized to current envelope after decode.
        XCTAssertEqual(payload.schemaVersion, ReminderRulesPayload.currentSchemaVersion)
        XCTAssertEqual(payload.rules.count, 1)
        XCTAssertNil(payload.snooze)
    }

    func testSchemaV1PayloadMigratesToV2() throws {
        let json = """
        {"schemaVersion":1,"rules":[{"id":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE","ruleType":"beforeEvent","offsetValue":1,"offsetUnit":"day","enabled":true}]}
        """
        let payload = try ReminderRuleCoding.decode(Data(json.utf8))
        XCTAssertEqual(payload.schemaVersion, 2)
        XCTAssertEqual(payload.rules.count, 1)
        XCTAssertNil(payload.rules[0].recurrence)
        XCTAssertNil(payload.rules[0].dateWindow)
    }

    func testRecurrenceRoundTrip() throws {
        let rule = ReminderRule.recurring(
            .weekly(weekdays: [2, 4]),
            window: ReminderDateWindow(
                startDate: DateComponents(year: 2026, month: 9, day: 1),
                endDate: DateComponents(year: 2026, month: 9, day: 30)
            )
        )
        let data = try ReminderRuleCoding.encode(rules: [rule], snooze: nil)
        let payload = try ReminderRuleCoding.decode(data)
        XCTAssertEqual(payload.rules.first?.recurrence?.frequency, .weekly)
        XCTAssertEqual(payload.rules.first?.dateWindow?.startDate.day, 1)
    }

    func testMalformedJSONThrows() {
        let data = Data("not-json".utf8)
        XCTAssertThrowsError(try ReminderRuleCoding.decode(data)) { error in
            XCTAssertEqual(error as? ReminderRuleCodingError, .malformed)
        }
    }

    func testUnsupportedVersionThrows() throws {
        let json = #"{"schemaVersion":99,"rules":[]}"#
        XCTAssertThrowsError(try ReminderRuleCoding.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ReminderRuleCodingError, .unsupportedVersion(99))
        }
    }

    func testMissingVersionThrows() throws {
        let json = #"{"rules":[]}"#
        XCTAssertThrowsError(try ReminderRuleCoding.decode(Data(json.utf8))) { error in
            XCTAssertEqual(error as? ReminderRuleCodingError, .missingVersion)
        }
    }

    func testEmptyObjectIsMalformedNotSilentEmpty() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try ReminderRuleCoding.decode(data))
    }
}

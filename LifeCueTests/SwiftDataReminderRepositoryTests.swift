import XCTest
import SwiftData
@testable import LifeCue

@MainActor
final class SwiftDataReminderRepositoryTests: XCTestCase {
    func testSwiftDataRoundTrip() async throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let repository = SwiftDataReminderRepository(modelContext: container.mainContext)
        let notifications = FakeNotificationScheduler()
        let service = ReminderService(
            repository: repository,
            notificationScheduler: notifications
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!

        let created = try await service.create(
            title: "Insurance renewal",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil,
            note: "Check policy number",
            rules: [
                .beforeEvent(value: 1, unit: .week),
                .beforeEvent(value: 1, unit: .day)
            ]
        ).reminder

        let fetched = try XCTUnwrap(repository.fetch(id: created.id))
        XCTAssertEqual(fetched.title, "Insurance renewal")
        XCTAssertEqual(fetched.note, "Check policy number")
        XCTAssertEqual(fetched.eventDate.year, 2026)
        XCTAssertEqual(fetched.eventDate.month, 9)
        XCTAssertEqual(fetched.eventDate.day, 18)
        XCTAssertEqual(fetched.rules.count, 2)

        try await service.delete(id: created.id)
        XCTAssertNil(try repository.fetch(id: created.id))
    }

    func testSnoozeStatePersistsSeparatelyFromRules() async throws {
        let container = try LifeCuePersistence.makeContainer(inMemory: true)
        let repository = SwiftDataReminderRepository(modelContext: container.mainContext)
        let service = ReminderService(
            repository: repository,
            notificationScheduler: FakeNotificationScheduler()
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18, hour: 16))!

        let created = try await service.create(
            title: "Snooze persist",
            eventDate: eventDate,
            includeTime: true,
            eventTime: eventDate,
            note: nil,
            rules: [.exactAtEvent(), .beforeEvent(value: 1, unit: .day)]
        ).reminder
        _ = try await service.snooze(id: created.id, option: .laterToday)

        let fetched = try XCTUnwrap(repository.fetch(id: created.id))
        XCTAssertEqual(fetched.rules.count, 2)
        XCTAssertNotNil(fetched.snooze)
    }
}

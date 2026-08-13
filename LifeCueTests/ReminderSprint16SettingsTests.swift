import XCTest
@testable import LifeCue

@MainActor
final class ReminderSprint16SettingsTests: XCTestCase {
    private var repository: InMemoryReminderRepository!
    private var notifications: FakeNotificationScheduler!
    private var service: ReminderService!
    private var calendar: Calendar!

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: LifeCueSettings.defaultReminderTimeKey)
        UserDefaults.standard.removeObject(forKey: LifeCueSettings.appearanceKey)

        repository = InMemoryReminderRepository()
        notifications = FakeNotificationScheduler()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        service = ReminderService(
            repository: repository,
            notificationScheduler: notifications,
            calendar: calendar
        )
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: LifeCueSettings.defaultReminderTimeKey)
        UserDefaults.standard.removeObject(forKey: LifeCueSettings.appearanceKey)
        super.tearDown()
    }

    // MARK: - Appearance

    func testDefaultAppearanceIsSystem() {
        XCTAssertEqual(LifeCueSettings.appearance, .system)
    }

    func testAppearanceCanBeChangedAndPersists() {
        LifeCueSettings.appearance = .dark
        XCTAssertEqual(LifeCueSettings.appearance, .dark)
        LifeCueSettings.appearance = .light
        XCTAssertEqual(LifeCueSettings.appearance, .light)
    }

    func testInvalidAppearanceFallsBackToSystem() {
        UserDefaults.standard.set("invalid-mode", forKey: LifeCueSettings.appearanceKey)
        XCTAssertEqual(LifeCueSettings.appearance, .system)
    }

    // MARK: - Default reminder time

    func testDefaultReminderTimeSafeDefault() {
        let components = LifeCueSettings.defaultReminderTime
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    func testChangingDefaultReminderTimeAffectsNewDateOnlyReminders() async throws {
        LifeCueSettings.defaultReminderTime = DateComponents(hour: 10, minute: 30)
        let eventDate = calendar.date(from: DateComponents(year: 2026, month: 9, day: 5))!
        let created = try await service.create(
            title: "Date only",
            eventDate: eventDate,
            includeTime: false,
            eventTime: nil
        ).reminder
        XCTAssertEqual(created.eventTime?.hour, 10)
        XCTAssertEqual(created.eventTime?.minute, 30)
    }

    func testChangingDefaultReminderTimeDoesNotModifyExistingReminders() async throws {
        let existing = Reminder(
            title: "Legacy date only",
            eventDate: DateComponents(year: 2026, month: 8, day: 20),
            eventTime: nil,
            timeZoneIdentifier: "Asia/Kolkata",
            rules: ReminderRule.productDefaults(includeExactAtEvent: false)
        )
        try repository.save(existing)

        LifeCueSettings.defaultReminderTime = DateComponents(hour: 14, minute: 15)
        let stored = try XCTUnwrap(service.reminder(id: existing.id))
        XCTAssertNil(stored.eventTime)
    }

    func testInvalidPersistedDefaultReminderTimeFallsBackSafely() {
        UserDefaults.standard.set(["hour": 99, "minute": -1], forKey: LifeCueSettings.defaultReminderTimeKey)
        let components = LifeCueSettings.defaultReminderTime
        XCTAssertEqual(components.hour, 9)
        XCTAssertEqual(components.minute, 0)
    }

    // MARK: - About

    func testAboutVersionComesFromBundleConfiguration() {
        XCTAssertFalse(LifeCueBundleInfo.marketingVersion.isEmpty)
        XCTAssertNotEqual(LifeCueBundleInfo.marketingVersion, "—")
    }

    func testAboutBuildComesFromBundleConfiguration() {
        XCTAssertFalse(LifeCueBundleInfo.buildNumber.isEmpty)
        XCTAssertNotEqual(LifeCueBundleInfo.buildNumber, "—")
    }

    func testAboutRequiredContentExists() {
        XCTAssertTrue(AboutLifeCueView.requiredFeatureList.contains("Backup & Restore"))
        XCTAssertEqual(AboutLifeCueView.tagline, "Simple, local-first reminder management.")
    }

    // MARK: - Privacy

    func testPrivacyExpectedContentExists() {
        XCTAssertFalse(PrivacyContent.statements.isEmpty)
        XCTAssertTrue(PrivacyContent.statements.contains(where: { $0.contains("stored locally") }))
        XCTAssertTrue(PrivacyContent.statements.contains(where: { $0.contains("does not require an account") }))
    }

    func testPrivacyImageExtractionWordingPresent() {
        XCTAssertTrue(
            PrivacyContent.statements.contains(where: { $0.localizedCaseInsensitiveContains("image") || $0.localizedCaseInsensitiveContains("photo") })
        )
    }

    // MARK: - Notification display

    func testNotificationAuthorizationDisplayLabels() {
        XCTAssertEqual(NotificationAuthorizationDisplay.label(for: .authorized), "Allowed")
        XCTAssertEqual(NotificationAuthorizationDisplay.label(for: .denied), "Denied")
        XCTAssertEqual(NotificationAuthorizationDisplay.label(for: .notDetermined), "Not Determined")
    }

    // MARK: - More navigation contracts

    func testMoreHelpToolbarPresentation() {
        XCTAssertEqual(MoreNavigationPresentation.helpToolbarAccessibilityLabel, "Help")
        XCTAssertEqual(MoreNavigationPresentation.helpToolbarSystemImage, "questionmark.circle")
    }

    func testMoreMenuItemsPresentation() {
        XCTAssertEqual(MoreNavigationPresentation.settingsLabel, "Settings")
        XCTAssertEqual(MoreNavigationPresentation.peopleLabel, "People")
        XCTAssertEqual(MoreNavigationPresentation.contextsLabel, "Contexts")
        XCTAssertEqual(MoreNavigationPresentation.backupRestoreLabel, "Backup & Restore")
    }
}

@MainActor
final class ReminderSprint16HelpTests: XCTestCase {
    private let removedQuestionIDs = [
        "cr-title", "cr-date", "cr-time",
        "cr-repeat-once", "cr-repeat-daily", "cr-repeat-weekly", "cr-repeat-monthly",
        "cr-weekdays",
        "cr-remind-10min", "cr-remind-1hr", "cr-remind-1day", "cr-remind-1week",
        "cr-note",
        "notif-background", "notif-tap",
        "cal-permission",
        "bk-replace", "bk-reminder-what"
    ]

    private let removedQuestionTexts = [
        "What is Title?",
        "What is Date?",
        "What is Time?",
        "What does Once mean?",
        "What does Every day mean?",
        "What does Every week mean?",
        "What does Every month mean?",
        "Can I select more than one weekday?",
        "What does 10 minutes before mean?",
        "What does 1 hour before mean?",
        "What does 1 day before mean?",
        "What does 1 week before mean?",
        "What is Note?",
        "Will reminders notify me when LifeCue is not open?",
        "What happens when I tap a reminder notification?",
        "When does LifeCue ask for Calendar permission?",
        "What happens during restore?",
        "What is Backup Reminder?"
    ]

    private func question(id: String) -> HelpQuestion? {
        HelpContent.allQuestions.first { $0.id == id }
    }

    func testHelpContentExists() {
        XCTAssertFalse(HelpContent.sections.isEmpty)
    }

    func testRemovedQuestionsAreAbsentByID() {
        for id in removedQuestionIDs {
            XCTAssertNil(question(id: id), "Expected removed question id: \(id)")
        }
    }

    func testRemovedQuestionsAreAbsentByText() {
        let allText = HelpContent.allQuestions.map(\.question)
        for text in removedQuestionTexts {
            XCTAssertFalse(allText.contains(text), "Expected removed question: \(text)")
        }
    }

    func testImageExtractionSectionExists() {
        XCTAssertNotNil(HelpContent.sections.first { $0.id == "image-extraction" })
        XCTAssertEqual(
            HelpContent.sections.first { $0.id == "image-extraction" }?.title,
            "Image Extraction"
        )
    }

    func testImageExtractionTerminologyUsed() {
        let section = HelpContent.sections.first { $0.id == "image-extraction" }
        XCTAssertNotNil(section?.questions.first { $0.id == "ie-accuracy" })
        XCTAssertTrue(
            section?.questions.contains(where: { $0.question.localizedCaseInsensitiveContains("image extraction") }) == true
        )
    }

    func testOCRUserFacingTerminologyAbsentFromHelp() {
        let combined = HelpContent.allQuestions.flatMap { [$0.question, $0.answer] }.joined(separator: " ")
        XCTAssertFalse(combined.contains("OCR"))
    }

    func testImageExtractionAccuracyWarningExists() {
        let item = question(id: "ie-accuracy")
        XCTAssertNotNil(item)
        XCTAssertTrue(item?.answer.localizedCaseInsensitiveContains("review") == true)
    }

    func testImageExtractionReviewGuidanceExists() {
        XCTAssertNotNil(question(id: "cr-review"))
        XCTAssertNotNil(question(id: "ie-why"))
    }

    func testPrivacyHelpHasNoObsoleteOCRWording() {
        let privacy = PrivacyContent.statements.joined(separator: " ")
        XCTAssertFalse(privacy.contains("OCR"))
    }
}

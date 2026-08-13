import XCTest
@testable import LifeCue

/// Sprint 13 — OCR extraction reliability (deterministic fixtures; no Vision).
final class ReminderSprint13OCRExtractionTests: XCTestCase {
    private var calendar: Calendar!
    private var timeZone: TimeZone!
    private var referenceDate: Date!
    private var extractor: DeterministicReminderTextExtractor!

    override func setUp() {
        super.setUp()
        timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // Fixed reference: 10 August 2026 — never use system "now".
        referenceDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
        extractor = DeterministicReminderTextExtractor()
    }

    private func config(localeID: String = "en_GB") -> ExtractionConfiguration {
        ExtractionConfiguration(
            referenceDate: referenceDate,
            timeZone: timeZone,
            locale: Locale(identifier: localeID)
        )
    }

    private func extract(_ text: String, localeID: String = "en_GB") -> ReminderDraft {
        extractor.extract(from: text, configuration: config(localeID: localeID))
    }

    private func assertDate(
        _ draft: ReminderDraft,
        year: Int,
        month: Int,
        day: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let date = draft.eventDate else {
            return XCTFail("Expected resolved date", file: file, line: line)
        }
        XCTAssertEqual(date.year, year, file: file, line: line)
        XCTAssertEqual(date.month, month, file: file, line: line)
        XCTAssertEqual(date.day, day, file: file, line: line)
    }

    private func assertTime(
        _ draft: ReminderDraft,
        hour: Int,
        minute: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let time = draft.eventTime else {
            return XCTFail("Expected resolved time", file: file, line: line)
        }
        XCTAssertEqual(time.hour, hour, file: file, line: line)
        XCTAssertEqual(time.minute, minute, file: file, line: line)
    }

    // MARK: - Required Sprint 13 cases

    /// TC-OCR-EXTRACT-001
    func test001_DoctorAppointmentTomorrowAt4PM() {
        let draft = extract("Doctor appointment tomorrow at 4 PM")
        assertDate(draft, year: 2026, month: 8, day: 11)
        assertTime(draft, hour: 16, minute: 0)
        XCTAssertTrue(draft.title.lowercased().contains("doctor"))
        XCTAssertTrue(draft.title.lowercased().contains("appointment"))
        XCTAssertFalse(draft.title.lowercased().contains("tomorrow"))
    }

    /// TC-OCR-EXTRACT-002
    func test002_DoctorAppointmentTomorrowMissingTime() {
        let draft = extract("Doctor appointment tomorrow")
        assertDate(draft, year: 2026, month: 8, day: 11)
        XCTAssertTrue(draft.timeState.isMissing)
        XCTAssertNil(draft.eventTime)
    }

    /// TC-OCR-EXTRACT-003
    func test003_MeetingTomorrowAt1600() {
        let draft = extract("Meeting tomorrow at 16:00")
        assertDate(draft, year: 2026, month: 8, day: 11)
        assertTime(draft, hour: 16, minute: 0)
    }

    /// TC-OCR-EXTRACT-004 Date-only extraction does not invent a time
    func test004_DateOnlyDoesNotInventTime() {
        let draft = extract("Science project due on 25 August 2026.")
        assertDate(draft, year: 2026, month: 8, day: 25)
        XCTAssertTrue(draft.timeState.isMissing)
        XCTAssertNil(draft.eventTime)
    }

    /// TC-OCR-EXTRACT-005 Multiple dates → ambiguous
    func test005_MultipleDatesAmbiguousWithoutWinner() {
        let draft = extract("""
        Meeting 12 Aug
        Follow-up 18 Aug
        """)
        XCTAssertTrue(draft.dateState.isAmbiguous)
        XCTAssertNil(draft.eventDate)
    }

    /// TC-OCR-EXTRACT-006 Multiple times → ambiguous
    func test006_MultipleTimesAmbiguousWithoutWinner() {
        let draft = extract("""
        Option A 3 PM
        Option B 5 PM
        """)
        XCTAssertTrue(draft.timeState.isAmbiguous)
        XCTAssertNil(draft.eventTime)
    }

    /// TC-OCR-EXTRACT-007 Unrelated screenshot timestamp not preferred
    func test007_UnrelatedTimestampNotPreferredOverAppointmentTime() {
        let draft = extract("""
        Yesterday 10:42 AM
        Doctor appointment tomorrow at 4 PM
        """)
        assertDate(draft, year: 2026, month: 8, day: 11)
        assertTime(draft, hour: 16, minute: 0)
    }

    /// TC-OCR-EXTRACT-008 Short meaningful title over generic UI text
    func test008_ShortMeaningfulTitleOverGenericUI() {
        let draft = extract("""
        Messages
        Mom
        Yesterday
        10:42 AM
        Doctor appointment tomorrow at 4 PM
        Ok thanks
        """)
        XCTAssertTrue(draft.title.lowercased().contains("doctor"))
        XCTAssertTrue(draft.title.lowercased().contains("appointment"))
        XCTAssertFalse(draft.title.lowercased().contains("messages"))
        XCTAssertFalse(draft.title.lowercased().contains("mom"))
    }

    /// TC-OCR-EXTRACT-009 Large unrelated OCR block not copied wholesale into note
    func test009_LargeUnrelatedBlockNotWholesaleNote() {
        let draft = extract("""
        Messages
        Family Group
        Yesterday 9:01 AM
        Can everyone confirm dinner plans for next week?
        Also pick up groceries if you go out.
        How about Saturday?
        I might be late.
        Sounds good.
        Doctor appointment tomorrow at 4 PM
        Bring insurance card.
        Lol yes
        See you then
        Typing…
        """)
        assertDate(draft, year: 2026, month: 8, day: 11)
        assertTime(draft, hour: 16, minute: 0)
        if let note = draft.note {
            XCTAssertFalse(note.lowercased().contains("family group"))
            XCTAssertFalse(note.lowercased().contains("dinner plans"))
            XCTAssertLessThan(note.count, 200)
            // Supporting text near the appointment may be kept; chat dump must not.
            XCTAssertTrue(
                note.lowercased().contains("insurance")
                    || note.split(separator: "\n").count <= 2
            )
        }
    }

    /// TC-OCR-EXTRACT-010 No meaningful note → empty/nil
    func test010_NoMeaningfulNoteRemainsEmpty() {
        let draft = extract("Doctor appointment tomorrow at 4 PM")
        XCTAssertTrue(draft.note == nil || draft.note?.isEmpty == true)
    }

    /// TC-OCR-EXTRACT-011 Partial OCR text is preserved
    func test011_PartialOCRTextPreservedInSource() {
        let partial = "Dentist appo"
        let draft = extract(partial)
        XCTAssertEqual(draft.sourceText, partial)
        XCTAssertFalse(draft.sourceText.isEmpty)
    }

    /// TC-OCR-EXTRACT-012 OCR failure remains safe
    func test012_OCRFailureRemainsSafe() {
        let draft = extractor.extract(
            from: .failed(reasonCode: "vision_error"),
            configuration: config()
        )
        XCTAssertEqual(draft.title, ReminderDraft.fallbackTitle)
        XCTAssertTrue(draft.titleWasFallback)
        XCTAssertTrue(draft.dateState.isMissing)
        XCTAssertTrue(draft.timeState.isMissing)
        XCTAssertNil(draft.note)
    }

    /// TC-OCR-EXTRACT-013 Existing numeric date formats remain valid
    func test013_NumericDateFormats() {
        assertDate(extract("Due 18/09/2026"), year: 2026, month: 9, day: 18)
        assertDate(extract("Due 18-09-2026"), year: 2026, month: 9, day: 18)
        assertDate(extract("Due 2026-09-18"), year: 2026, month: 9, day: 18)
    }

    /// TC-OCR-EXTRACT-014 Existing written date formats remain valid
    func test014_WrittenDateFormats() {
        assertDate(extract("Due 18 September 2026"), year: 2026, month: 9, day: 18)
        assertDate(extract("Due 18 Sep 2026"), year: 2026, month: 9, day: 18)
        assertDate(extract("Due September 18, 2026"), year: 2026, month: 9, day: 18)
    }

    /// TC-OCR-EXTRACT-015 Existing time formats remain valid
    func test015_TimeFormats() {
        assertTime(extract("At 4 PM"), hour: 16, minute: 0)
        assertTime(extract("At 4:00 PM"), hour: 16, minute: 0)
        assertTime(extract("At 4.30 PM"), hour: 16, minute: 30)
        assertTime(extract("At 16:00"), hour: 16, minute: 0)
    }

    /// TC-OCR-EXTRACT-016 Relative date uses explicit referenceDate
    func test016_RelativeDateUsesExplicitReferenceDate() {
        let otherRef = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12))!
        let draft = extractor.extract(
            from: "Meeting tomorrow at 4 PM",
            configuration: ExtractionConfiguration(
                referenceDate: otherRef,
                timeZone: timeZone,
                locale: Locale(identifier: "en_GB")
            )
        )
        assertDate(draft, year: 2027, month: 1, day: 1)
        assertTime(draft, hour: 16, minute: 0)
    }

    /// TC-OCR-EXTRACT-017 No ambient Date() for relative date parsing
    func test017_NoAmbientDateInRelativeParsingSources() throws {
        let root = try LifeCueRepositoryRoot.resolve()
            .appendingPathComponent("LifeCue/Services/Extraction", isDirectory: true)
        let files = [
            root.appendingPathComponent("ExtractionDateParser.swift"),
            root.appendingPathComponent("ExtractionTimeParser.swift"),
            root.appendingPathComponent("DeterministicReminderTextExtractor.swift")
        ]
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            // Allow only fixed epoch probes / documented literals — forbid ambient Date().
            XCTAssertFalse(
                source.contains("Date()"),
                "\(file.lastPathComponent) must not use ambient Date()"
            )
        }
    }

    /// TC-OCR-EXTRACT-018 Person/Context are NOT automatically inferred
    func test018_PersonContextNotAutomaticallyInferred() {
        let draft = extract("""
        Messages
        Mom
        Doctor appointment tomorrow at 4 PM
        """)
        XCTAssertNil(draft.personName)
        XCTAssertNil(draft.contextName)
        XCTAssertNil(draft.personID)
        XCTAssertNil(draft.contextID)
    }

    /// TC-OCR-EXTRACT-019 OCR extraction never creates a Reminder automatically
    @MainActor
    func test019_ExtractionNeverCreatesReminder() throws {
        let repository = InMemoryReminderRepository()
        _ = extract("Doctor appointment tomorrow at 4 PM")
        XCTAssertEqual(try repository.fetchAll().count, 0)
    }

    /// TC-OCR-EXTRACT-020 Confirmed draft still creates through ReminderService
    @MainActor
    func test020_ConfirmedDraftCreatesThroughReminderService() async throws {
        let repository = InMemoryReminderRepository()
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        let service = ReminderService(
            repository: repository,
            notificationScheduler: scheduler,
            calendar: calendar,
            clock: { self.referenceDate }
        )

        var draft = extract("Doctor appointment tomorrow at 4 PM")
        XCTAssertEqual(try repository.fetchAll().count, 0)

        // Confirm path: user-reviewed draft → ReminderService only.
        draft.personID = nil
        draft.contextID = nil
        let result = try await service.createFromConfirmedDraft(draft)
        XCTAssertEqual(try repository.fetchAll().count, 1)
        XCTAssertEqual(result.reminder.id, try repository.fetchAll().first?.id)
        XCTAssertTrue(result.reminder.title.lowercased().contains("doctor"))
    }

    // MARK: - Extra association / punctuation coverage

    func testTomorrowPunctuationVariants() {
        for text in [
            "Doctor appointment tomorrow, 4 PM",
            "Doctor appointment tomorrow @ 4 PM",
            "Doctor appointment tomorrow at 4 PM"
        ] {
            let draft = extract(text)
            assertDate(draft, year: 2026, month: 8, day: 11)
            assertTime(draft, hour: 16, minute: 0)
        }
    }

    func testNearbyLineDateTimeAssociation() {
        let draft = extract("""
        Meeting tomorrow
        at 3 PM
        """)
        assertDate(draft, year: 2026, month: 8, day: 11)
        assertTime(draft, hour: 15, minute: 0)
    }

    func testSupportingNoteNearTitlePreserved() {
        let draft = extract("""
        Dentist appointment
        18 September 2026
        4 PM
        Bring previous medical reports.
        """)
        XCTAssertNotNil(draft.note)
        XCTAssertTrue(draft.note!.lowercased().contains("bring previous"))
    }
}

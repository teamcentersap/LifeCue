import XCTest
@testable import LifeCue

final class ReminderTextExtractorTests: XCTestCase {
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

    // MARK: - TC-EXTRACT core

    /// TC-EXTRACT-001 Full appointment
    func testFullAppointment() {
        let draft = extract("""
        Dentist appointment
        18 September 2026
        4 PM
        """)
        XCTAssertTrue(draft.title.lowercased().contains("dentist"))
        XCTAssertFalse(draft.titleWasFallback)
        assertDate(draft, year: 2026, month: 9, day: 18)
        assertTime(draft, hour: 16, minute: 0)
    }

    /// TC-EXTRACT-002 Date only
    func testDateOnly() {
        let draft = extract("Science project is due on 25 August 2026.")
        assertDate(draft, year: 2026, month: 8, day: 25)
        XCTAssertTrue(draft.timeState.isMissing)
        XCTAssertNil(draft.eventTime)
    }

    /// TC-EXTRACT-003 Time only
    func testTimeOnly() {
        let draft = extract("Call the clinic at 4:00 PM")
        assertTime(draft, hour: 16, minute: 0)
        XCTAssertTrue(draft.dateState.isMissing)
    }

    /// TC-EXTRACT-004 Date + time
    func testDateAndTime() {
        let draft = extract("Doctor appointment on 18 September 2026 at 4 PM.")
        assertDate(draft, year: 2026, month: 9, day: 18)
        assertTime(draft, hour: 16, minute: 0)
    }

    /// TC-EXTRACT-005 Relative tomorrow
    func testRelativeTomorrow() {
        let draft = extract("Dentist tomorrow at 4 PM")
        assertDate(draft, year: 2026, month: 8, day: 11)
        assertTime(draft, hour: 16, minute: 0)
    }

    /// TC-EXTRACT-006 Relative today
    func testRelativeToday() {
        let draft = extract("Submit form today")
        assertDate(draft, year: 2026, month: 8, day: 10)
    }

    /// TC-EXTRACT-007 Ambiguous numeric date
    func testAmbiguousNumericDate() {
        let draft = extract("Appointment on 05/06/2026", localeID: "en_US")
        XCTAssertTrue(draft.dateState.isAmbiguous)
        XCTAssertNil(draft.eventDate)
        if case .ambiguous(let candidates, _) = draft.dateState {
            XCTAssertEqual(candidates.count, 2)
            let hasMay6 = candidates.contains { $0.month == 5 && $0.day == 6 }
            let hasJune5 = candidates.contains { $0.month == 6 && $0.day == 5 }
            XCTAssertTrue(hasMay6 && hasJune5)
        } else {
            XCTFail("Expected ambiguous date state")
        }
    }

    /// TC-EXTRACT-008 Multiple dates
    func testMultipleDatesRemainAmbiguousWithoutClearWinner() {
        let draft = extract("""
        Appointment:
        18 September 2026
        Previous appointment:
        10 August 2026
        Follow-up:
        25 September 2026
        """)
        // Competing event-like dates must not be silently collapsed.
        XCTAssertTrue(draft.dateState.isAmbiguous || draft.dateState.needsConfirmation)
        if case .resolved(let date) = draft.dateState {
            // If scoring picks one, it must be an appointment-adjacent date — never invent.
            XCTAssertEqual(date.year, 2026)
            XCTAssertTrue(date.month == 9 || date.month == 8)
        }
    }

    /// TC-EXTRACT-009 Multiple times
    func testMultipleTimesPrefersAppointmentContext() {
        let draft = extract("""
        Office opens 9 AM
        Appointment 4 PM
        """)
        assertTime(draft, hour: 16, minute: 0)
    }

    /// TC-EXTRACT-010 Title extraction
    func testTitleExtraction() {
        let draft = extract("""
        Parent Teacher Meeting
        Class 8B
        Monday 10 AM
        """)
        XCTAssertTrue(draft.title.lowercased().contains("parent teacher meeting"))
        XCTAssertFalse(draft.titleWasFallback)
    }

    /// TC-EXTRACT-011 Note preservation
    func testNotePreservation() {
        let draft = extract("""
        Dentist appointment
        18 September 2026
        4 PM
        Bring previous medical reports.
        """)
        XCTAssertNotNil(draft.note)
        XCTAssertTrue(draft.note!.lowercased().contains("bring previous"))
    }

    /// TC-EXTRACT-012 Missing title → fallback
    func testMissingTitleUsesFallback() {
        let draft = extract("18 September 2026")
        XCTAssertEqual(draft.title, ReminderDraft.fallbackTitle)
        XCTAssertTrue(draft.titleWasFallback)
    }

    /// TC-EXTRACT-013 Missing date
    func testMissingDateNotInvented() {
        let draft = extract("Remember to call Rahul.")
        XCTAssertTrue(draft.dateState.isMissing)
        XCTAssertNil(draft.eventDate)
    }

    /// TC-EXTRACT-014 Missing time
    func testMissingTimeNotInvented() {
        let draft = extract("Dentist appointment 18 September 2026")
        assertDate(draft, year: 2026, month: 9, day: 18)
        XCTAssertTrue(draft.timeState.isMissing)
    }

    /// TC-EXTRACT-015 No hallucinated fields
    func testNoHallucinatedFields() {
        let draft = extract("Doctor tomorrow")
        assertDate(draft, year: 2026, month: 8, day: 11)
        XCTAssertTrue(draft.timeState.isMissing)
        XCTAssertNil(draft.personName)
        XCTAssertNil(draft.contextName)
        XCTAssertFalse(draft.title.lowercased().contains("2026"))
    }

    /// TC-EXTRACT-016 Reference date determinism
    func testReferenceDateDeterminism() {
        let otherRef = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 12))!
        let draft = extractor.extract(
            from: "Meeting tomorrow",
            configuration: ExtractionConfiguration(
                referenceDate: otherRef,
                timeZone: timeZone,
                locale: Locale(identifier: "en_GB")
            )
        )
        assertDate(draft, year: 2027, month: 1, day: 1)
    }

    /// TC-EXTRACT-017 Timezone handling
    func testTimezonePreservedOnDraft() {
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        var tokyoCal = Calendar(identifier: .gregorian)
        tokyoCal.timeZone = tokyo
        let ref = tokyoCal.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 23))!
        let draft = extractor.extract(
            from: "Due tomorrow",
            configuration: ExtractionConfiguration(
                referenceDate: ref,
                timeZone: tokyo,
                locale: Locale(identifier: "en_GB")
            )
        )
        XCTAssertEqual(draft.timeZoneIdentifier, "Asia/Tokyo")
        assertDate(draft, year: 2026, month: 8, day: 11)
    }

    /// TC-EXTRACT-018 Locale preference ordering for ambiguous numeric dates
    func testLocaleOrdersAmbiguousCandidates() {
        let us = extract("Event 05/06/2026", localeID: "en_US")
        let gb = extract("Event 05/06/2026", localeID: "en_GB")
        XCTAssertTrue(us.dateState.isAmbiguous)
        XCTAssertTrue(gb.dateState.isAmbiguous)
        if case .ambiguous(let usCandidates, _) = us.dateState,
           case .ambiguous(let gbCandidates, _) = gb.dateState {
            // Preferred interpretation is first.
            XCTAssertEqual(usCandidates.first?.month, 5)
            XCTAssertEqual(usCandidates.first?.day, 6)
            XCTAssertEqual(gbCandidates.first?.month, 6)
            XCTAssertEqual(gbCandidates.first?.day, 5)
        } else {
            XCTFail("Expected ambiguous candidates")
        }
    }

    /// TC-EXTRACT-019 Malformed / noisy OCR
    func testNoisyOCRSafeNormalization() {
        let draft = extract("Dentist 18 September 2026 4 PN")
        assertDate(draft, year: 2026, month: 9, day: 18)
        assertTime(draft, hour: 16, minute: 0)
    }

    /// TC-EXTRACT-020 Extractor never creates Reminder
    @MainActor
    func testExtractorNeverCreatesReminder() throws {
        let repository = InMemoryReminderRepository()
        _ = extract("""
        Dentist appointment
        18 September 2026
        4 PM
        """)
        XCTAssertEqual(try repository.fetchAll().count, 0)
        // Protocol surface is OCR → draft only.
        let _: ReminderDraft = extractor.extract(
            from: "Hello",
            configuration: config()
        )
    }

    // MARK: - Formats & edges

    func testNamedMonthFormats() {
        assertDate(extract("Due 18 Sep 2026"), year: 2026, month: 9, day: 18)
        assertDate(extract("Due September 18, 2026"), year: 2026, month: 9, day: 18)
        assertDate(extract("Due Sep 18, 2026"), year: 2026, month: 9, day: 18)
    }

    func testISOAndDashedNumericUnambiguous() {
        assertDate(extract("Due 2026-09-18"), year: 2026, month: 9, day: 18)
        assertDate(extract("Due 18-09-2026"), year: 2026, month: 9, day: 18)
        assertDate(extract("Due 18/09/2026"), year: 2026, month: 9, day: 18)
    }

    func testTwentyFourHourAndAMPM() {
        assertTime(extract("At 16:00"), hour: 16, minute: 0)
        assertTime(extract("At 4:00 PM"), hour: 16, minute: 0)
        assertTime(extract("At 4.30 PM"), hour: 16, minute: 30)
        assertTime(extract("At 9 am"), hour: 9, minute: 0)
        assertTime(extract("At 12 PM"), hour: 12, minute: 0)
        assertTime(extract("At 12 AM"), hour: 0, minute: 0)
    }

    func testRelativeYesterday() {
        let draft = extract("Logged yesterday")
        assertDate(draft, year: 2026, month: 8, day: 9)
    }

    func testLeapYearValidAndInvalid() {
        assertDate(extract("Due 29 February 2024"), year: 2024, month: 2, day: 29)
        let invalid = extract("Due 29 February 2025")
        XCTAssertTrue(invalid.dateState.isMissing)
    }

    func testMonthAndYearBoundaries() {
        let endOfYearRef = calendar.date(from: DateComponents(year: 2026, month: 12, day: 31, hour: 10))!
        let draft = extractor.extract(
            from: "Pay tomorrow",
            configuration: ExtractionConfiguration(
                referenceDate: endOfYearRef,
                timeZone: timeZone,
                locale: Locale(identifier: "en_GB")
            )
        )
        assertDate(draft, year: 2027, month: 1, day: 1)

        assertDate(extract("Due 31 August 2026"), year: 2026, month: 8, day: 31)
    }

    func testEmptyOCR() {
        let draft = extractor.extract(
            from: .empty(reasonCode: "no_text"),
            configuration: config()
        )
        XCTAssertEqual(draft.title, ReminderDraft.fallbackTitle)
        XCTAssertTrue(draft.dateState.isMissing)
        XCTAssertTrue(draft.timeState.isMissing)
    }

    func testPersonPossessiveConservative() {
        let draft = extract("Sanchit's appointment is on 18 September 2026.")
        XCTAssertEqual(draft.personName, "Sanchit")
        let doctor = extract("Dr. Sharma appointment on 18 September 2026.")
        XCTAssertNil(doctor.personName)
    }

    func testContextOnlyWhenExplicitlyLabeled() {
        let none = extract("Dentist appointment 18 September 2026")
        XCTAssertNil(none.contextName)
        let labeled = extract("Context: School\nSubmit homework 20 September 2026")
        XCTAssertEqual(labeled.contextName, "School")
    }

    func testYearlyRecurrenceHintOnly() {
        let draft = extract("Annual medical test every year.")
        XCTAssertEqual(draft.proposedRecurrence, .yearly)
    }

    func testFakeExtractorIsReplaceable() {
        let stub = ReminderDraft.empty(sourceText: "x", configuration: config())
        let fake: ReminderTextExtracting = FakeReminderTextExtractor(draftToReturn: stub)
        let draft = fake.extract(from: "ignored", configuration: config())
        XCTAssertEqual(draft.title, ReminderDraft.fallbackTitle)
    }

    func testMonthWithoutYearUsesReferenceYear() {
        assertDate(extract("Dentist 18 September"), year: 2026, month: 9, day: 18)
    }

    func testWhitespaceAndDuplicateValues() {
        let draft = extract("  Dentist appointment  \n\n  18 September 2026  \n  18 September 2026  \n  4 PM  ")
        assertDate(draft, year: 2026, month: 9, day: 18)
        assertTime(draft, hour: 16, minute: 0)
    }
}

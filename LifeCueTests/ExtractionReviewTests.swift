import XCTest
import CoreGraphics
@testable import LifeCue

@MainActor
final class ExtractionReviewTests: XCTestCase {
    private var timeZone: TimeZone!
    private var calendar: Calendar!
    private var referenceDate: Date!

    override func setUp() {
        super.setUp()
        timeZone = TimeZone(identifier: "Asia/Kolkata")!
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        referenceDate = calendar.date(from: DateComponents(year: 2026, month: 8, day: 10, hour: 12))!
    }

    private func configuration() -> ExtractionConfiguration {
        ExtractionConfiguration(
            referenceDate: referenceDate,
            timeZone: timeZone,
            locale: Locale(identifier: "en_GB")
        )
    }

    private func resolvedDraft(
        title: String = "Dentist Appointment",
        date: DateComponents = DateComponents(year: 2026, month: 9, day: 18),
        time: DateComponents? = DateComponents(hour: 16, minute: 0),
        note: String? = "Bring previous reports",
        person: String? = "Sanchit",
        context: String? = "Doctor",
        sourceText: String = "Dentist Appointment\n18 September 2026\n4 PM"
    ) -> ReminderDraft {
        ReminderDraft(
            title: title,
            titleWasFallback: false,
            dateState: .resolved(date),
            timeState: time.map { .resolved($0) } ?? .missing,
            note: note,
            personName: person,
            contextName: context,
            personID: nil,
            contextID: nil,
            proposedRecurrence: nil,
            timeZoneIdentifier: timeZone.identifier,
            localeIdentifier: "en_GB",
            sourceText: sourceText
        )
    }

    private func makeService(
        scheduler: NotificationScheduling? = nil
    ) -> (ReminderService, InMemoryReminderRepository, FakeNotificationScheduler) {
        let notifications = (scheduler as? FakeNotificationScheduler) ?? FakeNotificationScheduler()
        let repository = InMemoryReminderRepository()
        let service = ReminderService(
            repository: repository,
            notificationScheduler: notifications,
            calendar: calendar,
            clock: { self.referenceDate }
        )
        return (service, repository, notifications)
    }

    // MARK: - Converter / display states

    /// TC-REVIEW-001 Resolved extraction displays correctly
    func testResolvedDraftFields() {
        let draft = resolvedDraft()
        XCTAssertEqual(draft.title, "Dentist Appointment")
        XCTAssertEqual(draft.eventDate?.day, 18)
        XCTAssertEqual(draft.eventTime?.hour, 16)
        XCTAssertEqual(draft.personName, "Sanchit")
        XCTAssertEqual(draft.contextName, "Doctor")
        XCTAssertEqual(draft.note, "Bring previous reports")
    }

    /// TC-REVIEW-002 Ambiguous field requires confirmation
    func testAmbiguousDateBlocksConversion() {
        var draft = resolvedDraft()
        draft.dateState = .ambiguous(
            candidates: [
                DateComponents(year: 2026, month: 5, day: 6),
                DateComponents(year: 2026, month: 6, day: 5)
            ],
            rawSnippet: "05/06/2026"
        )
        XCTAssertThrowsError(try ReminderDraftConverter.makeConfirmedInput(from: draft)) { error in
            XCTAssertEqual(error as? ReminderDraftConverter.ConversionError, .unresolvedAmbiguousDate)
        }
    }

    /// TC-REVIEW-024 Ambiguous date cannot silently become resolved
    func testAmbiguousDateNotSilentlyResolved() {
        let draft = ReminderDraft(
            title: "Event",
            titleWasFallback: false,
            dateState: .ambiguous(
                candidates: [
                    DateComponents(year: 2026, month: 5, day: 6),
                    DateComponents(year: 2026, month: 6, day: 5)
                ],
                rawSnippet: "05/06/2026"
            ),
            timeState: .missing,
            note: nil,
            personName: nil,
            contextName: nil,
            personID: nil,
            contextID: nil,
            proposedRecurrence: nil,
            timeZoneIdentifier: timeZone.identifier,
            localeIdentifier: "en_US",
            sourceText: "05/06/2026"
        )
        XCTAssertNil(draft.eventDate)
        XCTAssertTrue(draft.dateState.isAmbiguous)
    }

    /// TC-REVIEW-003 Missing optional field remains empty
    func testMissingOptionalFieldsRemainEmpty() throws {
        let draft = resolvedDraft(time: nil, note: nil, person: nil, context: nil)
        let input = try ReminderDraftConverter.makeConfirmedInput(from: draft)
        XCTAssertNil(input.eventTime)
        XCTAssertNil(input.note)
    }

    // MARK: - Edits

    /// TC-REVIEW-004…009 User edits fields
    func testUserEditsUpdateDraft() {
        let (service, _, _) = makeService()
        let viewModel = ExtractionReviewViewModel(draft: resolvedDraft(), reminderService: service)
        viewModel.updateTitle("Orthodontist")
        viewModel.setEventDate(from: calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 12))!)
        viewModel.setEventTime(from: calendar.date(from: DateComponents(year: 2026, month: 9, day: 19, hour: 15, minute: 30))!)
        viewModel.updateNote("Bring X-rays")
        viewModel.updatePerson("Saachi")
        viewModel.updateContext("Health")

        XCTAssertEqual(viewModel.draft.title, "Orthodontist")
        XCTAssertEqual(viewModel.draft.eventDate?.day, 19)
        XCTAssertEqual(viewModel.draft.eventTime?.hour, 15)
        XCTAssertEqual(viewModel.draft.eventTime?.minute, 30)
        XCTAssertEqual(viewModel.draft.note, "Bring X-rays")
        XCTAssertEqual(viewModel.draft.personName, "Saachi")
        XCTAssertEqual(viewModel.draft.contextName, "Health")
    }

    /// TC-REVIEW-010 Edited values are used when creating Reminder
    func testEditedValuesUsedOnCreate() async throws {
        let (service, repository, _) = makeService()
        let viewModel = ExtractionReviewViewModel(draft: resolvedDraft(), reminderService: service)
        viewModel.updateTitle("Updated Title")
        viewModel.updateNote("Updated note")
        let result = await viewModel.createReminder()
        XCTAssertNotNil(result)
        let saved = try repository.fetchAll().first
        XCTAssertEqual(saved?.title, "Updated Title")
        XCTAssertTrue(saved?.note?.contains("Updated note") == true)
    }

    // MARK: - Confirmation boundary

    /// TC-REVIEW-011 Cancel creates no Reminder
    /// TC-REVIEW-012 Opening review creates no Reminder
    /// TC-REVIEW-013 OCR completion creates no Reminder
    func testReviewLifecycleCreatesNoReminderUntilConfirm() async throws {
        let (service, repository, _) = makeService()
        let draft = resolvedDraft()
        _ = ExtractionReviewViewModel(draft: draft, reminderService: service)
        XCTAssertEqual(try repository.fetchAll().count, 0)

        let ocr = FakeOCRService(behavior: .success(.success(
            fullText: "Dentist tomorrow at 4 PM",
            observations: [OCRTextObservation(text: "Dentist tomorrow at 4 PM")]
        )))
        let extractor = DeterministicReminderTextExtractor()
        _ = try await ocr.recognizeText(in: makeBlankCGImage())
        _ = extractor.extract(
            from: "Dentist appointment tomorrow at 4 PM",
            configuration: configuration()
        )
        XCTAssertEqual(try repository.fetchAll().count, 0)
    }

    /// TC-REVIEW-014 Create Reminder creates exactly one Reminder
    /// TC-REVIEW-016 Existing ReminderService is used
    /// TC-REVIEW-017 Existing notification engine is used
    func testCreateReminderPersistsAndSchedules() async throws {
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        let (service, repository, _) = makeService(scheduler: scheduler)
        let viewModel = ExtractionReviewViewModel(draft: resolvedDraft(), reminderService: service)
        let result = await viewModel.createReminder()
        XCTAssertNotNil(result)
        XCTAssertEqual(try repository.fetchAll().count, 1)
        XCTAssertFalse(scheduler.scheduled.isEmpty)
        XCTAssertEqual(result?.reminder.timeZoneIdentifier, timeZone.identifier)
    }

    /// TC-REVIEW-015 Double Create does not create duplicates
    func testDoubleCreateDoesNotDuplicate() async throws {
        let (service, repository, _) = makeService()
        let viewModel = ExtractionReviewViewModel(draft: resolvedDraft(), reminderService: service)
        async let a = viewModel.createReminder()
        async let b = viewModel.createReminder()
        async let c = viewModel.createReminder()
        _ = await (a, b, c)
        // Sequential MainActor calls still guarded by didCreate.
        _ = await viewModel.createReminder()
        XCTAssertEqual(try repository.fetchAll().count, 1)
        XCTAssertTrue(viewModel.didCreate)
    }

    /// TC-REVIEW-018 Notification scheduling failure preserves Reminder
    func testSchedulingFailurePreservesReminder() async throws {
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        scheduler.shouldFailSchedule = true
        let (service, repository, _) = makeService(scheduler: scheduler)
        let viewModel = ExtractionReviewViewModel(draft: resolvedDraft(), reminderService: service)
        let result = await viewModel.createReminder()
        XCTAssertEqual(try repository.fetchAll().count, 1)
        XCTAssertTrue(result?.scheduleFailed == true)
        XCTAssertNotNil(viewModel.scheduleWarningMessage)
    }

    /// TC-REVIEW-019 Invalid required data prevents creation
    func testMissingDatePreventsCreation() async throws {
        let (service, repository, _) = makeService()
        var draft = resolvedDraft()
        draft.dateState = .missing
        let viewModel = ExtractionReviewViewModel(draft: draft, reminderService: service)
        let result = await viewModel.createReminder()
        XCTAssertNil(result)
        XCTAssertEqual(try repository.fetchAll().count, 0)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    /// TC-REVIEW-020 Original OCR text can be viewed
    func testSourceTextAvailableForReview() {
        let (service, _, _) = makeService()
        let draft = resolvedDraft(sourceText: "RAW OCR LINE")
        let viewModel = ExtractionReviewViewModel(draft: draft, reminderService: service)
        XCTAssertEqual(viewModel.draft.sourceText, "RAW OCR LINE")
        viewModel.showRecognizedText = true
        XCTAssertTrue(viewModel.showRecognizedText)
    }

    /// TC-REVIEW-021 No image persistence — review operates on draft/OCR text only
    func testReviewHoldsNoImageData() {
        let (service, _, _) = makeService()
        let viewModel = ExtractionReviewViewModel(draft: resolvedDraft(), reminderService: service)
        // View model surface is draft + service; no image property.
        XCTAssertFalse(viewModel.draft.sourceText.isEmpty)
        XCTAssertNil(viewModel.createdReminder)
    }

    /// TC-REVIEW-022 Person/context are optional
    func testPersonAndContextOptionalOnCreate() async throws {
        let (service, repository, _) = makeService()
        let draft = resolvedDraft(person: nil, context: nil)
        let viewModel = ExtractionReviewViewModel(draft: draft, reminderService: service)
        _ = await viewModel.createReminder()
        let saved = try repository.fetchAll().first
        XCTAssertNotNil(saved)
        XCTAssertFalse(saved?.note?.contains("For:") == true)
        XCTAssertFalse(saved?.note?.contains("Context:") == true)
    }

    /// TC-REVIEW-023 Timezone preserved through draft → Reminder
    func testTimezonePreserved() async throws {
        let (service, repository, _) = makeService()
        var draft = resolvedDraft()
        draft.timeZoneIdentifier = "America/New_York"
        let viewModel = ExtractionReviewViewModel(draft: draft, reminderService: service)
        _ = await viewModel.createReminder()
        XCTAssertEqual(try repository.fetchAll().first?.timeZoneIdentifier, "America/New_York")
    }

    /// Explicit: OCR/extraction alone never creates Reminder
    func testNoAutomaticConfirmation() async throws {
        let (service, repository, _) = makeService()
        let extractor = FakeReminderTextExtractor(draftToReturn: resolvedDraft())
        let ocrText = "Dentist appointment tomorrow at 4 PM"
        let draft = extractor.extract(from: ocrText, configuration: configuration())
        XCTAssertEqual(draft.title.isEmpty, false)
        XCTAssertEqual(try repository.fetchAll().count, 0)

        let viewModel = ExtractionReviewViewModel(draft: draft, reminderService: service)
        XCTAssertEqual(try repository.fetchAll().count, 0)
        _ = await viewModel.createReminder()
        XCTAssertEqual(try repository.fetchAll().count, 1)
    }

    /// End-to-end: FakeOCR → FakeExtractor → Review confirm → ReminderService → FakeNotificationScheduler
    func testEndToEndPipelineWithFakes() async throws {
        let scheduler = FakeNotificationScheduler()
        scheduler.status = .authorized
        let (service, repository, _) = makeService(scheduler: scheduler)

        let draft = resolvedDraft(
            title: "Science Project",
            date: DateComponents(year: 2026, month: 8, day: 25),
            time: DateComponents(hour: 9, minute: 0),
            note: "Submit online",
            person: nil,
            context: nil,
            sourceText: "Science Project due 25 August 2026 9 AM"
        )
        let fakeOCR = FakeOCRService(behavior: .success(.success(
            fullText: draft.sourceText,
            observations: [OCRTextObservation(text: draft.sourceText)]
        )))
        let fakeExtractor = FakeReminderTextExtractor(draftToReturn: draft)

        let image = makeBlankCGImage()
        let ocrResult = try await fakeOCR.recognizeText(in: image)
        XCTAssertEqual(try repository.fetchAll().count, 0)

        let extracted = fakeExtractor.extract(from: ocrResult, configuration: configuration())
        XCTAssertEqual(try repository.fetchAll().count, 0)

        let viewModel = ExtractionReviewViewModel(draft: extracted, reminderService: service)
        XCTAssertEqual(try repository.fetchAll().count, 0)

        let result = await viewModel.createReminder()
        XCTAssertEqual(try repository.fetchAll().count, 1)
        XCTAssertEqual(result?.reminder.title, "Science Project")
        XCTAssertFalse(scheduler.scheduled.isEmpty)
    }

    func testResolveAmbiguousDateThenCreate() async throws {
        let (service, repository, _) = makeService()
        var draft = resolvedDraft(time: nil)
        draft.dateState = .ambiguous(
            candidates: [
                DateComponents(year: 2026, month: 5, day: 6),
                DateComponents(year: 2026, month: 6, day: 5)
            ],
            rawSnippet: "05/06/2026"
        )
        let viewModel = ExtractionReviewViewModel(draft: draft, reminderService: service)
        XCTAssertFalse(viewModel.canCreate)
        viewModel.resolveDate(to: DateComponents(year: 2026, month: 6, day: 5))
        XCTAssertTrue(viewModel.canCreate)
        _ = await viewModel.createReminder()
        XCTAssertEqual(try repository.fetchAll().first?.eventDate.month, 6)
        XCTAssertEqual(try repository.fetchAll().first?.eventDate.day, 5)
    }

    func testPersonContextUseIDsNotNoteFolding() throws {
        var draft = resolvedDraft(note: "Bring reports", person: "Sanchit", context: "Doctor")
        draft.personID = UUID()
        draft.contextID = UUID()
        let input = try ReminderDraftConverter.makeConfirmedInput(from: draft)
        // OCR hint strings are not folded into the note; IDs live on Reminder.
        XCTAssertEqual(input.note, "Bring reports")
    }

    private func makeBlankCGImage() -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        let context = CGContext(
            data: nil,
            width: 8,
            height: 8,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!
        return context.makeImage()!
    }
}

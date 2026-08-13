import Foundation
import Observation

/// Review/edit/confirm for an extraction ReminderDraft. Never creates a Reminder until `createReminder()`.
@MainActor
@Observable
final class ExtractionReviewViewModel {
    private(set) var draft: ReminderDraft
    private let reminderService: ReminderService

    private(set) var isCreating = false
    /// Once true, further Create taps are ignored (double-submit protection).
    private(set) var didCreate = false
    private(set) var createdReminder: Reminder?
    private(set) var lastMutationResult: ReminderMutationResult?

    var errorMessage: String?
    var scheduleWarningMessage: String?
    var showRecognizedText = false

    /// UI: whether the user wants an event time.
    var includeTime: Bool {
        didSet {
            if !includeTime {
                draft.timeState = .missing
            } else if draft.timeState.isMissing {
                // Do not invent a time — wait for picker / resolution.
            }
        }
    }

    init(draft: ReminderDraft, reminderService: ReminderService) {
        self.draft = draft
        self.reminderService = reminderService
        self.includeTime = draft.hasResolvedTime || draft.timeState.isAmbiguous
    }

    var canCreate: Bool {
        let titleOK = !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let dateOK = draft.hasResolvedDate
        let timeOK = !draft.timeState.isAmbiguous
        return titleOK && dateOK && timeOK && !isCreating && !didCreate
    }

    var dateStatusLabel: String {
        switch draft.dateState {
        case .resolved: return "Detected"
        case .ambiguous: return "Needs confirmation"
        case .missing: return "Not detected"
        }
    }

    var timeStatusLabel: String {
        switch draft.timeState {
        case .resolved: return "Detected"
        case .ambiguous: return "Needs confirmation"
        case .missing: return "Not detected"
        }
    }

    // MARK: - Edits (authoritative; no OCR re-run)

    func updateTitle(_ title: String) {
        draft.title = title
        draft.titleWasFallback = false
    }

    func updateNote(_ note: String) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.note = trimmed.isEmpty ? nil : trimmed
    }

    func updatePerson(_ person: String) {
        let trimmed = person.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.personName = trimmed.isEmpty ? nil : trimmed
    }

    func updateContext(_ context: String) {
        let trimmed = context.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.contextName = trimmed.isEmpty ? nil : trimmed
    }

    func selectPersonID(_ id: UUID?) {
        draft.personID = id
    }

    func selectContextID(_ id: UUID?) {
        draft.contextID = id
    }

    /// Resolves ambiguity by explicit user choice — never silent.
    func resolveDate(to components: DateComponents) {
        draft.dateState = .resolved(Reminder.normalizedDate(components))
    }

    func resolveTime(to components: DateComponents) {
        includeTime = true
        draft.timeState = .resolved(Reminder.normalizedTime(components))
    }

    func clearTime() {
        includeTime = false
        draft.timeState = .missing
    }

    func setEventDate(from date: Date) {
        let comps = Reminder.dateComponents(from: date, calendar: draftCalendar)
        draft.dateState = .resolved(comps)
    }

    func setEventTime(from date: Date) {
        includeTime = true
        let comps = Reminder.timeComponents(from: date, calendar: draftCalendar)
        draft.timeState = .resolved(comps)
    }

    var draftCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: draft.timeZoneIdentifier) ?? .current
        return calendar
    }

    /// Date binding helper for DatePicker (draft timezone wall clock).
    var pickerDate: Date {
        get {
            if let resolved = draft.eventDate,
               let date = draftCalendar.date(from: DateComponents(
                year: resolved.year,
                month: resolved.month,
                day: resolved.day,
                hour: 12,
                minute: 0
               )) {
                return date
            }
            return draftCalendar.startOfDay(for: Date())
        }
        set { setEventDate(from: newValue) }
    }

    var pickerTime: Date {
        get {
            var comps = draftCalendar.dateComponents([.year, .month, .day], from: pickerDate)
            if let time = draft.eventTime {
                comps.hour = time.hour
                comps.minute = time.minute
            } else {
                comps.hour = 9
                comps.minute = 0
            }
            return draftCalendar.date(from: comps) ?? pickerDate
        }
        set { setEventTime(from: newValue) }
    }

    var ambiguousDateCandidates: [DateComponents] {
        if case .ambiguous(let candidates, _) = draft.dateState {
            return candidates
        }
        return []
    }

    var ambiguousTimeCandidates: [DateComponents] {
        if case .ambiguous(let candidates, _) = draft.timeState {
            return candidates
        }
        return []
    }

    // MARK: - Confirmation

    @discardableResult
    func createReminder() async -> ReminderMutationResult? {
        guard !isCreating, !didCreate else { return lastMutationResult }
        isCreating = true
        errorMessage = nil
        scheduleWarningMessage = nil
        defer { isCreating = false }

        do {
            let result = try await reminderService.createFromConfirmedDraft(draft)
            didCreate = true
            createdReminder = result.reminder
            lastMutationResult = result
            if result.scheduleFailed {
                scheduleWarningMessage =
                    "The reminder was saved, but notifications could not be scheduled. You can try again later."
            }
            return result
        } catch let error as LocalizedError {
            errorMessage = error.errorDescription ?? "Couldn't create the reminder."
            return nil
        } catch {
            errorMessage = "Couldn't create the reminder."
            return nil
        }
    }
}

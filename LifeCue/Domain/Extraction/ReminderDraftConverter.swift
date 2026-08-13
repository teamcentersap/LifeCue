import Foundation

/// Pure conversion from a user-confirmed ReminderDraft into Reminder factory inputs.
/// Does not persist or schedule anything.
enum ReminderDraftConverter {
    enum ConversionError: Error, Equatable, LocalizedError {
        case emptyTitle
        case missingEventDate
        case unresolvedAmbiguousDate
        case unresolvedAmbiguousTime

        var errorDescription: String? {
            switch self {
            case .emptyTitle:
                return "Title is required."
            case .missingEventDate:
                return "A date is required."
            case .unresolvedAmbiguousDate:
                return "Please confirm the date."
            case .unresolvedAmbiguousTime:
                return "Please confirm the time."
            }
        }
    }

    struct ConfirmedReminderInput: Equatable, Sendable {
        let title: String
        let eventDate: DateComponents
        let eventTime: DateComponents?
        let timeZoneIdentifier: String
        let note: String?
        let includeExactAtEvent: Bool
    }

    /// Validates draft confirmation state. Does not invent missing values.
    static func makeConfirmedInput(from draft: ReminderDraft) throws -> ConfirmedReminderInput {
        let trimmedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw ConversionError.emptyTitle }

        switch draft.dateState {
        case .missing:
            throw ConversionError.missingEventDate
        case .ambiguous:
            throw ConversionError.unresolvedAmbiguousDate
        case .resolved(let date):
            guard date.year != nil, date.month != nil, date.day != nil else {
                throw ConversionError.missingEventDate
            }

            let eventTime: DateComponents?
            switch draft.timeState {
            case .missing:
                eventTime = nil
            case .ambiguous:
                throw ConversionError.unresolvedAmbiguousTime
            case .resolved(let time):
                eventTime = Reminder.normalizedTime(time)
            }

            return ConfirmedReminderInput(
                title: trimmedTitle,
                eventDate: Reminder.normalizedDate(date),
                eventTime: eventTime,
                timeZoneIdentifier: draft.timeZoneIdentifier,
                note: composeNote(from: draft),
                includeExactAtEvent: eventTime != nil
            )
        }
    }

    /// Note only. Person/Context are assigned via IDs on the Reminder (Sprint 7).
    static func composeNote(from draft: ReminderDraft) -> String? {
        normalizedOptional(draft.note)
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

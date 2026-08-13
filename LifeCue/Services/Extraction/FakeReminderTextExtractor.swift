import Foundation

/// Test double. Never invents reminder fields beyond the configured draft.
final class FakeReminderTextExtractor: ReminderTextExtracting, @unchecked Sendable {
    var draftToReturn: ReminderDraft
    private(set) var extractCallCount = 0
    private(set) var lastSourceText: String?

    init(draftToReturn: ReminderDraft) {
        self.draftToReturn = draftToReturn
    }

    func extract(from result: OCRResult, configuration: ExtractionConfiguration) -> ReminderDraft {
        extractCallCount += 1
        lastSourceText = result.fullText
        return draftToReturn
    }
}

import Foundation

/// Abstraction for deterministic OCR → draft extraction. Never creates reminders.
protocol ReminderTextExtracting: AnyObject {
    func extract(from result: OCRResult, configuration: ExtractionConfiguration) -> ReminderDraft
}

extension ReminderTextExtracting {
    func extract(from text: String, configuration: ExtractionConfiguration) -> ReminderDraft {
        let result = OCRResult.success(
            fullText: text,
            observations: text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { OCRTextObservation(text: String($0)) }
        )
        return extract(from: result, configuration: configuration)
    }
}

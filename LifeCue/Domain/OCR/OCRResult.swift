import Foundation
import CoreGraphics

/// Outcome of local Vision OCR. No reminder semantics.
enum OCRStatus: Equatable, Sendable {
    case success
    case empty
    case failed
}

/// A single recognized text block with geometry for later extraction (Sprint 4).
struct OCRTextObservation: Equatable, Sendable, Identifiable {
    let id: UUID
    let text: String
    /// Normalized bounding box in Vision coordinates (origin bottom-left), if available.
    let boundingBox: CGRect?
    let confidence: Float?

    init(
        id: UUID = UUID(),
        text: String,
        boundingBox: CGRect? = nil,
        confidence: Float? = nil
    ) {
        self.id = id
        self.text = text
        self.boundingBox = boundingBox
        self.confidence = confidence
    }
}

/// Structured OCR result. Independent from Reminder / extraction.
struct OCRResult: Equatable, Sendable {
    let status: OCRStatus
    /// Full text in approximate reading order (newline-separated).
    let fullText: String
    let observations: [OCRTextObservation]
    /// Non-sensitive machine reason for empty/failed; never log user image content.
    let failureReasonCode: String?

    var hasRecognizedText: Bool {
        !fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func success(fullText: String, observations: [OCRTextObservation]) -> OCRResult {
        OCRResult(
            status: observations.isEmpty && fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .empty
                : .success,
            fullText: fullText,
            observations: observations,
            failureReasonCode: nil
        )
    }

    static func empty(reasonCode: String = "no_text") -> OCRResult {
        OCRResult(status: .empty, fullText: "", observations: [], failureReasonCode: reasonCode)
    }

    static func failed(reasonCode: String) -> OCRResult {
        OCRResult(status: .failed, fullText: "", observations: [], failureReasonCode: reasonCode)
    }
}

enum OCRServiceError: Error, Equatable, LocalizedError {
    case invalidImage
    case processingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Couldn't read that image."
        case .processingFailed:
            return "Couldn't read text from this image."
        }
    }
}

import Foundation
import CoreGraphics

/// Deterministic OCR double for unit tests. Never invents reminder fields.
final class FakeOCRService: OCRServing, @unchecked Sendable {
    enum Behavior: Sendable {
        case success(OCRResult)
        case empty
        case failure
        case throwInvalidImage
    }

    var behavior: Behavior
    private(set) var recognizeCallCount = 0
    private(set) var lastImageWidth: Int?
    private(set) var lastImageHeight: Int?

    init(behavior: Behavior = .empty) {
        self.behavior = behavior
    }

    func recognizeText(in image: CGImage) async throws -> OCRResult {
        recognizeCallCount += 1
        lastImageWidth = image.width
        lastImageHeight = image.height

        switch behavior {
        case .success(let result):
            return result
        case .empty:
            return .empty(reasonCode: "fake_empty")
        case .failure:
            return .failed(reasonCode: "fake_failed")
        case .throwInvalidImage:
            throw OCRServiceError.invalidImage
        }
    }
}

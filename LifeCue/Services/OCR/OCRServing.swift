import Foundation
import CoreGraphics

/// Abstraction for on-device OCR. Views must not call Vision directly.
protocol OCRServing: AnyObject {
    /// Recognizes text in an image. Must not create reminders or invent fields.
    func recognizeText(in image: CGImage) async throws -> OCRResult
}

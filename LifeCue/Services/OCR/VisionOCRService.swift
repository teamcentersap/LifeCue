import Foundation
import CoreGraphics
import ImageIO
import Vision

/// Local Apple Vision OCR. No network. No reminder creation.
final class VisionOCRService: OCRServing, @unchecked Sendable {
    private let recognitionLevel: VNRequestTextRecognitionLevel
    private let usesLanguageCorrection: Bool
    private let minimumTextHeight: Float?

    init(
        recognitionLevel: VNRequestTextRecognitionLevel = .accurate,
        usesLanguageCorrection: Bool = true,
        minimumTextHeight: Float? = nil
    ) {
        self.recognitionLevel = recognitionLevel
        self.usesLanguageCorrection = usesLanguageCorrection
        self.minimumTextHeight = minimumTextHeight
    }

    func recognizeText(in image: CGImage) async throws -> OCRResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try self.performRecognition(on: image)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func performRecognition(on image: CGImage) throws -> OCRResult {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = usesLanguageCorrection
        if let minimumTextHeight {
            request.minimumTextHeight = minimumTextHeight
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            // Do not include Vision/error payloads that might echo image content.
            throw OCRServiceError.processingFailed
        }

        guard let observations = request.results, !observations.isEmpty else {
            return .empty(reasonCode: "no_observations")
        }

        // Sort top-to-bottom, then left-to-right (Vision box origin is bottom-left).
        let sorted = observations.sorted { lhs, rhs in
            let l = lhs.boundingBox
            let r = rhs.boundingBox
            if abs(l.maxY - r.maxY) > 0.02 {
                return l.maxY > r.maxY
            }
            return l.minX < r.minX
        }

        var lines: [OCRTextObservation] = []
        for observation in sorted {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            lines.append(
                OCRTextObservation(
                    text: text,
                    boundingBox: observation.boundingBox,
                    confidence: candidate.confidence
                )
            )
        }

        if lines.isEmpty {
            return .empty(reasonCode: "empty_candidates")
        }

        let fullText = lines.map(\.text).joined(separator: "\n")
        return .success(fullText: fullText, observations: lines)
    }
}

enum CaptureImagePreparing {
    /// Downscales very large images for OCR while preserving aspect ratio.
    static func prepareCGImage(from data: Data, maxPixelDimension: CGFloat = 2048) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

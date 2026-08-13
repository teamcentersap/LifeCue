import Foundation
import CoreGraphics
import Observation

@MainActor
@Observable
final class ImageCaptureViewModel {
    enum Phase: Equatable {
        case idle
        case processing
        case result(OCRResult)
        case failed(String)
    }

    private let ocrService: OCRServing
    private(set) var phase: Phase = .idle
    private(set) var isProcessing = false

    init(ocrService: OCRServing) {
        self.ocrService = ocrService
    }

    func reset() {
        phase = .idle
        isProcessing = false
    }

    /// Runs OCR on image data. Does not create reminders.
    func processImageData(_ data: Data) async {
        guard !isProcessing else { return }
        isProcessing = true
        phase = .processing
        defer { isProcessing = false }

        guard let cgImage = CaptureImagePreparing.prepareCGImage(from: data) else {
            phase = .failed("Couldn't read that image.")
            return
        }

        do {
            let result = try await ocrService.recognizeText(in: cgImage)
            switch result.status {
            case .success:
                phase = .result(result)
            case .empty:
                phase = .failed("Couldn't read text from this image.")
            case .failed:
                phase = .failed("Couldn't read text from this image.")
            }
        } catch let error as LocalizedError {
            phase = .failed(error.errorDescription ?? "Couldn't read text from this image.")
        } catch {
            phase = .failed("Couldn't read text from this image.")
        }
    }

    func processCGImage(_ image: CGImage) async {
        guard !isProcessing else { return }
        isProcessing = true
        phase = .processing
        defer { isProcessing = false }

        do {
            let result = try await ocrService.recognizeText(in: image)
            switch result.status {
            case .success:
                phase = .result(result)
            case .empty, .failed:
                phase = .failed("Couldn't read text from this image.")
            }
        } catch let error as LocalizedError {
            phase = .failed(error.errorDescription ?? "Couldn't read text from this image.")
        } catch {
            phase = .failed("Couldn't read text from this image.")
        }
    }
}

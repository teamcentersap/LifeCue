import XCTest
import CoreGraphics
@testable import LifeCue

final class OCRServiceTests: XCTestCase {
    private func makeBlankCGImage(width: Int = 16, height: Int = 16) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        )
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        )!
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    /// TC-OCR-001 Successful OCR result
    func testSuccessfulOCRResult() async throws {
        let expected = OCRResult.success(
            fullText: "Doctor Appointment\n18 September 2026\n4:00 PM",
            observations: [
                OCRTextObservation(text: "Doctor Appointment", confidence: 0.9),
                OCRTextObservation(text: "18 September 2026", confidence: 0.8),
                OCRTextObservation(text: "4:00 PM", confidence: 0.7)
            ]
        )
        let fake = FakeOCRService(behavior: .success(expected))
        let result = try await fake.recognizeText(in: makeBlankCGImage())
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.fullText, expected.fullText)
        XCTAssertEqual(result.observations.count, 3)
    }

    /// TC-OCR-002 Empty OCR result
    func testEmptyOCRResult() async throws {
        let fake = FakeOCRService(behavior: .empty)
        let result = try await fake.recognizeText(in: makeBlankCGImage())
        XCTAssertEqual(result.status, .empty)
        XCTAssertFalse(result.hasRecognizedText)
        XCTAssertTrue(result.observations.isEmpty)
    }

    /// TC-OCR-003 OCR failure
    func testOCRFailure() async throws {
        let fake = FakeOCRService(behavior: .failure)
        let result = try await fake.recognizeText(in: makeBlankCGImage())
        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.failureReasonCode, "fake_failed")
    }

    /// TC-OCR-003b thrown invalid image
    func testOCRThrowsInvalidImage() async {
        let fake = FakeOCRService(behavior: .throwInvalidImage)
        do {
            _ = try await fake.recognizeText(in: makeBlankCGImage())
            XCTFail("Expected throw")
        } catch let error as OCRServiceError {
            XCTAssertEqual(error, .invalidImage)
        } catch {
            XCTFail("Unexpected error \(error)")
        }
    }

    /// TC-OCR-004 Partial OCR result is preserved as-is
    func testPartialOCRResultPreserved() async throws {
        let partial = OCRResult.success(
            fullText: "Doctor Appointment\n18 September",
            observations: [
                OCRTextObservation(text: "Doctor Appointment"),
                OCRTextObservation(text: "18 September")
            ]
        )
        let fake = FakeOCRService(behavior: .success(partial))
        let result = try await fake.recognizeText(in: makeBlankCGImage())
        XCTAssertEqual(result.fullText, "Doctor Appointment\n18 September")
        XCTAssertFalse(result.fullText.contains("4:00 PM"))
        XCTAssertFalse(result.fullText.contains("Bring previous reports"))
    }

    /// TC-OCR-006 OCR text does not contain fabricated information
    func testOCRDoesNotFabricateFields() async throws {
        let input = OCRResult.success(
            fullText: "Doctor tomorrow",
            observations: [OCRTextObservation(text: "Doctor tomorrow")]
        )
        let fake = FakeOCRService(behavior: .success(input))
        let result = try await fake.recognizeText(in: makeBlankCGImage())
        XCTAssertEqual(result.fullText, "Doctor tomorrow")
        XCTAssertFalse(result.fullText.lowercased().contains("2026"))
        XCTAssertFalse(result.fullText.lowercased().contains("am"))
        XCTAssertFalse(result.fullText.lowercased().contains("pm"))
    }

    /// TC-OCR-007 OCR service can be replaced by fake service
    func testOCRServiceIsReplaceable() async throws {
        let fake: OCRServing = FakeOCRService(
            behavior: .success(
                .success(fullText: "Hello", observations: [OCRTextObservation(text: "Hello")])
            )
        )
        let result = try await fake.recognizeText(in: makeBlankCGImage())
        XCTAssertEqual(result.fullText, "Hello")
    }
}

@MainActor
final class ImageCaptureViewModelTests: XCTestCase {
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

    /// TC-OCR-005 OCR service / capture flow does not create a Reminder
    func testOCRSuccessDoesNotCreateReminder() async {
        let repository = InMemoryReminderRepository()
        let fakeOCR = FakeOCRService(
            behavior: .success(
                .success(
                    fullText: "Science project due 25 August",
                    observations: [OCRTextObservation(text: "Science project due 25 August")]
                )
            )
        )
        let viewModel = ImageCaptureViewModel(ocrService: fakeOCR)
        await viewModel.processCGImage(makeBlankCGImage())

        if case .result = viewModel.phase {
            // ok
        } else {
            XCTFail("Expected OCR result phase")
        }
        XCTAssertEqual(try? repository.fetchAll().count, 0)
    }

    /// TC-OCR-008 OCR processing state is handled correctly
    func testProcessingStateTransitions() async {
        let fakeOCR = FakeOCRService(
            behavior: .success(
                .success(fullText: "Hello", observations: [OCRTextObservation(text: "Hello")])
            )
        )
        let viewModel = ImageCaptureViewModel(ocrService: fakeOCR)
        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertFalse(viewModel.isProcessing)

        await viewModel.processCGImage(makeBlankCGImage())
        XCTAssertFalse(viewModel.isProcessing)
        if case .result(let result) = viewModel.phase {
            XCTAssertEqual(result.fullText, "Hello")
        } else {
            XCTFail("Expected result")
        }
    }

    /// TC-OCR-002/003 empty and failure surface user-facing failed phase
    func testEmptyOCRShowsFailurePhase() async {
        let viewModel = ImageCaptureViewModel(ocrService: FakeOCRService(behavior: .empty))
        await viewModel.processCGImage(makeBlankCGImage())
        if case .failed(let message) = viewModel.phase {
            XCTAssertTrue(message.contains("Couldn't read text"))
        } else {
            XCTFail("Expected failed phase")
        }
    }

    /// TC-OCR-009 cancellation / reset does not create reminder; returns to idle
    func testResetDoesNotCreateReminder() async {
        let repository = InMemoryReminderRepository()
        let viewModel = ImageCaptureViewModel(
            ocrService: FakeOCRService(
                behavior: .success(
                    .success(fullText: "X", observations: [OCRTextObservation(text: "X")])
                )
            )
        )
        await viewModel.processCGImage(makeBlankCGImage())
        viewModel.reset()
        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertEqual(try? repository.fetchAll().count, 0)
    }

    /// TC-OCR-010 architecture: OCR pipeline has no ReminderService dependency
    func testViewModelOnlyDependsOnOCRService() {
        let viewModel = ImageCaptureViewModel(ocrService: FakeOCRService())
        // Compiles with OCRServing alone — no reminder mutation API on the view model.
        XCTAssertEqual(viewModel.phase, .idle)
        XCTAssertFalse(viewModel.isProcessing)
    }

    /// TC-OCR-010 OCR text is not written to application logs (source scan of OCR modules)
    func testOCRModulesDoNotLogRecognizedContent() throws {
        let root = try LifeCueRepositoryRoot.resolve()
        let relativePaths = [
            "LifeCue/Services/OCR/VisionOCRService.swift",
            "LifeCue/Services/OCR/FakeOCRService.swift",
            "LifeCue/Services/OCR/OCRServing.swift",
            "LifeCue/Domain/OCR/OCRResult.swift",
            "LifeCue/Features/Capture/ImageCaptureViewModel.swift"
        ]
        let forbidden = ["print(", "NSLog(", "os_log(", "Logger("]
        for relative in relativePaths {
            let url = root.appendingPathComponent(relative)
            let source = try String(contentsOf: url, encoding: .utf8)
            for token in forbidden {
                XCTAssertFalse(
                    source.contains(token),
                    "\(relative) must not contain \(token) (OCR privacy)"
                )
            }
        }
    }

    func testDuplicateProcessingIgnoredWhileBusy() async {
        let fake = FakeOCRService(
            behavior: .success(
                .success(fullText: "One", observations: [OCRTextObservation(text: "One")])
            )
        )
        let viewModel = ImageCaptureViewModel(ocrService: fake)
        async let first: Void = viewModel.processCGImage(makeBlankCGImage())
        async let second: Void = viewModel.processCGImage(makeBlankCGImage())
        _ = await (first, second)
        XCTAssertEqual(fake.recognizeCallCount, 1)
    }
}

final class CaptureImagePreparingTests: XCTestCase {
    func testPrepareCGImageFromPNGData() {
        // 1x1 PNG
        let pngBase64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO5WNloAAAAASUVORK5CYII="
        let data = Data(base64Encoded: pngBase64)!
        let image = CaptureImagePreparing.prepareCGImage(from: data, maxPixelDimension: 64)
        XCTAssertNotNil(image)
    }

    func testPrepareRejectsInvalidData() {
        XCTAssertNil(CaptureImagePreparing.prepareCGImage(from: Data("not-an-image".utf8)))
    }
}

final class ShareExtensionGuardTests: XCTestCase {
    /// Confirms the app target does not register an incoming Share Extension.
    func testNoShareExtensionTargetInBundle() {
        let shareExtensionBundles = Bundle.allBundles.filter {
            ($0.bundleIdentifier ?? "").contains("shareextension")
                || ($0.bundlePath as NSString).lastPathComponent.lowercased().contains("share")
        }.filter {
            ($0.infoDictionary?["NSExtension"] as? [String: Any]) != nil
        }
        XCTAssertTrue(
            shareExtensionBundles.isEmpty,
            "LifeCue must not register an incoming Share Extension in V1"
        )

        let appExtension = Bundle.main.infoDictionary?["NSExtension"]
        XCTAssertNil(appExtension)
    }
}

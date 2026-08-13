import SwiftUI
import PhotosUI

struct ImageCaptureFlowView: View {
    enum Source: String {
        case library
        case camera
    }

    let reminderService: ReminderService
    let personService: PersonService
    let contextService: ContextService
    let ocrService: OCRServing
    let textExtractor: ReminderTextExtracting
    let initialSource: Source
    var onReminderCreated: () -> Void
    var onManualFallback: () -> Void
    var onClose: () -> Void

    @State private var viewModel: ImageCaptureViewModel
    @State private var reviewViewModel: ExtractionReviewViewModel?
    @State private var pickerItem: PhotosPickerItem?
    @State private var showPhotosPicker = false
    @State private var showCamera = false
    @State private var didAutoPresent = false
    @State private var cameraUnavailableMessage: String?
    @State private var loadError: String?

    init(
        reminderService: ReminderService,
        personService: PersonService,
        contextService: ContextService,
        ocrService: OCRServing,
        textExtractor: ReminderTextExtracting,
        initialSource: Source,
        onReminderCreated: @escaping () -> Void,
        onManualFallback: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.reminderService = reminderService
        self.personService = personService
        self.contextService = contextService
        self.ocrService = ocrService
        self.textExtractor = textExtractor
        self.initialSource = initialSource
        self.onReminderCreated = onReminderCreated
        self.onManualFallback = onManualFallback
        self.onClose = onClose
        _viewModel = State(initialValue: ImageCaptureViewModel(ocrService: ocrService))
    }

    var body: some View {
        NavigationStack {
            content
                .background(LifeCueTheme.background.ignoresSafeArea())
                .navigationTitle(navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            reviewViewModel = nil
                            viewModel.reset()
                            onClose()
                        }
                        .disabled(viewModel.isProcessing || (reviewViewModel?.isCreating ?? false))
                    }
                }
                .onAppear {
                    guard !didAutoPresent else { return }
                    didAutoPresent = true
                    switch initialSource {
                    case .library:
                        showPhotosPicker = true
                    case .camera:
                        startCamera()
                    }
                }
                .photosPicker(
                    isPresented: $showPhotosPicker,
                    selection: $pickerItem,
                    matching: .images
                )
                .onChange(of: pickerItem) { _, newItem in
                    guard let newItem else { return }
                    Task { await handlePickedItem(newItem) }
                }
                .onChange(of: viewModel.phase) { _, phase in
                    if case .result(let result) = phase {
                        let draft = textExtractor.extract(
                            from: result,
                            configuration: ExtractionConfiguration(
                                referenceDate: Date(),
                                timeZone: .current,
                                locale: .current
                            )
                        )
                        // Review only — OCR/extraction must not create a Reminder.
                        reviewViewModel = ExtractionReviewViewModel(
                            draft: draft,
                            reminderService: reminderService
                        )
                    } else {
                        reviewViewModel = nil
                    }
                }
                .fullScreenCover(isPresented: $showCamera) {
                    CameraPickerView { data in
                        showCamera = false
                        if let data {
                            Task { await viewModel.processImageData(data) }
                        }
                    }
                    .ignoresSafeArea()
                }
                .alert(
                    "Camera unavailable",
                    isPresented: Binding(
                        get: { cameraUnavailableMessage != nil },
                        set: { if !$0 { cameraUnavailableMessage = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { cameraUnavailableMessage = nil }
                } message: {
                    Text(cameraUnavailableMessage ?? "")
                }
                .alert(
                    "Couldn't load image",
                    isPresented: Binding(
                        get: { loadError != nil },
                        set: { if !$0 { loadError = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) { loadError = nil }
                } message: {
                    Text(loadError ?? "")
                }
        }
    }

    private var navigationTitle: String {
        if reviewViewModel != nil { return "Review" }
        return "Add from Image"
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.phase {
        case .idle:
            sourceChooser
        case .processing:
            processingView
        case .result:
            if let reviewViewModel {
                ExtractionReviewView(
                    viewModel: reviewViewModel,
                    personService: personService,
                    contextService: contextService,
                    onCreated: { _ in
                        self.reviewViewModel = nil
                        viewModel.reset()
                        onReminderCreated()
                    },
                    onCancel: {
                        self.reviewViewModel = nil
                        viewModel.reset()
                        onClose()
                    },
                    onTryAnother: {
                        self.reviewViewModel = nil
                        viewModel.reset()
                    },
                    onAddManually: {
                        self.reviewViewModel = nil
                        viewModel.reset()
                        onClose()
                        onManualFallback()
                    }
                )
            } else {
                ProgressView()
            }
        case .failed(let message):
            OCRFailureView(
                message: message,
                onTryAnother: { viewModel.reset() },
                onAddManually: {
                    viewModel.reset()
                    onClose()
                    onManualFallback()
                }
            )
        }
    }

    private var sourceChooser: some View {
        VStack(spacing: 16) {
            Text("Choose an image inside LifeCue. Images are read on this device only.")
                .font(LifeCueTheme.bodyFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                showPhotosPicker = true
            } label: {
                labelRow(title: "Upload Image", systemImage: "photo")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)

            Button {
                startCamera()
            } label: {
                labelRow(title: "Take Photo", systemImage: "camera")
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isProcessing)

            Spacer()
        }
        .padding(20)
    }

    private var processingView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
            Text("Reading text…")
                .font(LifeCueTheme.bodyFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func labelRow(title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(LifeCueTheme.today)
            Text(title)
                .foregroundStyle(LifeCueTheme.primaryText)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(LifeCueTheme.secondaryText)
        }
        .padding(16)
        .lifeCueCard()
    }

    private func startCamera() {
        guard CameraPickerView.isCameraAvailable else {
            cameraUnavailableMessage = "Camera is not available on this device. You can upload an image instead."
            return
        }
        showCamera = true
    }

    private func handlePickedItem(_ item: PhotosPickerItem) async {
        do {
            if let loaded = try await item.loadTransferable(type: TransferableImageData.self) {
                await viewModel.processImageData(loaded.data)
            } else {
                loadError = "Couldn't load the selected image."
            }
        } catch {
            loadError = "Couldn't load the selected image."
        }
        pickerItem = nil
    }
}

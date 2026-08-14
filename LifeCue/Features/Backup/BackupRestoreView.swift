import SwiftUI

@MainActor
final class BackupRestoreViewModel: ObservableObject {
    @Published var lastExportCreatedOnThisDevice: Date?
    @Published var exportCounts: BackupInventoryCounts?
    @Published var isExporting = false
    @Published var isImporting = false
    @Published var exportDocument: LifeCueBackupFileDocument?
    @Published var exportFileName = BackupFileNaming.suggestedFileName(for: Date())
    @Published var showExporter = false
    @Published var importPreview: BackupImportPreview?
    @Published var showImportSummary = false
    @Published var showReplaceConfirmation = false
    @Published var errorMessage: String?
    @Published var infoMessage: String?

    @Published var backupReminderEnabled = false
    @Published var backupReminderInterval: BackupReminderInterval = .oneWeek
    @Published var notificationPermissionDenied = false

    private let exportService: BackupExportServing
    private let importService: BackupImportServing
    private let backupReminderScheduler: BackupReminderScheduler?
    private let onDataChanged: () -> Void

    init(
        exportService: BackupExportServing,
        importService: BackupImportServing,
        backupReminderScheduler: BackupReminderScheduler? = nil,
        onDataChanged: @escaping () -> Void = {}
    ) {
        self.exportService = exportService
        self.importService = importService
        self.backupReminderScheduler = backupReminderScheduler
        self.onDataChanged = onDataChanged
        self.lastExportCreatedOnThisDevice = BackupExportMetadata.lastExportCreatedOnThisDevice
        if let backupReminderScheduler {
            backupReminderEnabled = backupReminderScheduler.isEnabled
            backupReminderInterval = backupReminderScheduler.interval
        }
    }

    func setBackupReminderEnabled(_ enabled: Bool) async {
        guard let scheduler = backupReminderScheduler else { return }
        if enabled {
            let status = await scheduler.enable()
            notificationPermissionDenied = status == .denied || status == .unsupported
        } else {
            await scheduler.disable()
            notificationPermissionDenied = false
        }
        backupReminderEnabled = scheduler.isEnabled
        backupReminderInterval = scheduler.interval
    }

    func setBackupReminderInterval(_ interval: BackupReminderInterval) async {
        guard let scheduler = backupReminderScheduler else { return }
        await scheduler.setInterval(interval)
        backupReminderInterval = scheduler.interval
    }

    func prepareExport() {
        errorMessage = nil
        infoMessage = nil
        isExporting = true
        defer { isExporting = false }
        do {
            let now = Date()
            let result = try exportService.exportBackup(exportedAt: now)
            exportCounts = result.counts
            exportDocument = LifeCueBackupFileDocument(data: result.data)
            exportFileName = BackupFileNaming.suggestedFileName(for: now)
            showExporter = true
        } catch {
            errorMessage = BackupUserFacingError.exportFailed.message
        }
    }

    func didFinishExport(result: Result<URL, Error>) {
        switch result {
        case .success:
            let now = Date()
            BackupExportMetadata.lastExportCreatedOnThisDevice = now
            lastExportCreatedOnThisDevice = now
            if backupReminderEnabled {
                Task { await backupReminderScheduler?.rescheduleAfterSuccessfulExport(at: now) }
            }
            if let counts = exportCounts {
                infoMessage = "Export created: \(counts.reminders) reminders, \(counts.people) people, \(counts.contexts) contexts."
            } else {
                infoMessage = "Export created on this device."
            }
        case .failure:
            // User cancel or system failure — do not claim success.
            break
        }
        exportDocument = nil
    }

    func handleImportedFile(url: URL) {
        errorMessage = nil
        infoMessage = nil
        isImporting = true
        defer { isImporting = false }

        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let attributes = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = attributes.fileSize {
                try BackupValidator.validateImportFileSize(fileSize)
            }
            let data = try Data(contentsOf: url)
            let preview = try importService.prepareImport(from: data)
            importPreview = preview
            showImportSummary = true
        } catch {
            importPreview = nil
            errorMessage = BackupUserFacingError.from(error).message
        }
    }

    func cancelImport() {
        importPreview = nil
        showImportSummary = false
        showReplaceConfirmation = false
    }

    func requestReplace() {
        guard importPreview != nil else { return }
        showReplaceConfirmation = true
    }

    func confirmReplace() async {
        guard let preview = importPreview else { return }
        showReplaceConfirmation = false
        errorMessage = nil
        do {
            let reconcileResult = try await importService.replace(with: preview)
            importPreview = nil
            showImportSummary = false
            infoMessage = BackupRestorePresentation.restoreMessage(for: reconcileResult)
            onDataChanged()
        } catch {
            // Store rolls back on failure; current data remains unchanged.
            errorMessage = BackupUserFacingError.restoreFailed.message
        }
    }
}

struct BackupRestoreView: View {
    @StateObject private var viewModel: BackupRestoreViewModel
    @State private var showImporter = false

    init(viewModel: BackupRestoreViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                Text("Protect your LifeCue reminders when changing or resetting phones.")
                    .font(LifeCueTheme.bodyFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
            }

            Section("Backup") {
                Button {
                    viewModel.prepareExport()
                } label: {
                    Label("Export Backup", systemImage: "square.and.arrow.up")
                }
                .disabled(viewModel.isExporting)

                Text("Create a portable copy of your reminders, People and Contexts.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)

                if let last = viewModel.lastExportCreatedOnThisDevice {
                    Text("Last export created on this device: \(last.formatted(date: .abbreviated, time: .shortened))")
                        .font(LifeCueTheme.captionFont)
                        .foregroundStyle(LifeCueTheme.secondaryText)
                }
            }

            Section("Backup Reminder") {
                Text("Get a reminder to create a backup periodically.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)

                Toggle(
                    "Remind me to create a backup",
                    isOn: Binding(
                        get: { viewModel.backupReminderEnabled },
                        set: { newValue in
                            Task { await viewModel.setBackupReminderEnabled(newValue) }
                        }
                    )
                )

                if viewModel.backupReminderEnabled {
                    Picker(
                        "Every",
                        selection: Binding(
                            get: { viewModel.backupReminderInterval },
                            set: { newValue in
                                Task { await viewModel.setBackupReminderInterval(newValue) }
                            }
                        )
                    ) {
                        ForEach(BackupReminderInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }

                    if viewModel.notificationPermissionDenied {
                        Text("Notifications are turned off for LifeCue. Enable notifications in Settings to receive backup reminders.")
                            .font(LifeCueTheme.captionFont)
                            .foregroundStyle(LifeCueTheme.overdue)
                    }

                    if let last = viewModel.lastExportCreatedOnThisDevice {
                        Text("Last backup created on this device: \(last.formatted(date: .abbreviated, time: .omitted))")
                            .font(LifeCueTheme.captionFont)
                            .foregroundStyle(LifeCueTheme.secondaryText)
                    } else {
                        Text("Last backup created on this device: Never")
                            .font(LifeCueTheme.captionFont)
                            .foregroundStyle(LifeCueTheme.secondaryText)
                    }
                }
            }

            Section("Restore") {
                Button {
                    showImporter = true
                } label: {
                    Label("Import Backup", systemImage: "square.and.arrow.down")
                }
                .disabled(viewModel.isImporting)

                Text("Restore LifeCue data from a previous backup.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
            }

            Section("Privacy") {
                Text("Your backup is a LifeCue file that you can save to Files, iCloud Drive, Google Drive, AirDrop, or another location you choose.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                Text("LifeCue does not upload your backup. You choose where to store it.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
            }

            if let info = viewModel.infoMessage {
                Section {
                    Text(info)
                        .font(LifeCueTheme.captionFont)
                        .foregroundStyle(LifeCueTheme.secondaryText)
                }
            }
        }
        .lifeCueFormContentWidth()
        .navigationTitle("Backup & Restore")
        .alert("Backup", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .fileExporter(
            isPresented: $viewModel.showExporter,
            document: viewModel.exportDocument,
            contentType: .lifeCueBackup,
            defaultFilename: viewModel.exportFileName.replacingOccurrences(of: ".lifecuebackup", with: "")
        ) { result in
            viewModel.didFinishExport(result: result)
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.lifeCueBackup, .json, .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    viewModel.handleImportedFile(url: url)
                }
            case .failure:
                viewModel.errorMessage = BackupUserFacingError.unreadable.message
            }
        }
        .sheet(isPresented: $viewModel.showImportSummary) {
            if let preview = viewModel.importPreview {
                ImportBackupSummaryView(
                    preview: preview,
                    onReplace: { viewModel.requestReplace() },
                    onCancel: { viewModel.cancelImport() }
                )
            }
        }
        .alert("Replace current LifeCue data?", isPresented: $viewModel.showReplaceConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                Task { await viewModel.confirmReplace() }
            }
        } message: {
            Text("This will replace the reminders, People and Contexts currently stored on this device.")
        }
    }
}

struct ImportBackupSummaryView: View {
    let preview: BackupImportPreview
    let onReplace: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("This backup contains") {
                    Text("\(preview.backupCounts.reminders) reminders")
                    Text("\(preview.backupCounts.people) people")
                    Text("\(preview.backupCounts.contexts) contexts")
                    if let exportedAt = preview.exportedAt {
                        Text("Created: \(exportedAt.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(LifeCueTheme.secondaryText)
                    }
                }

                Section("Your current LifeCue contains") {
                    Text("\(preview.currentCounts.reminders) reminders")
                    Text("\(preview.currentCounts.people) people")
                    Text("\(preview.currentCounts.contexts) contexts")
                }

                Section {
                    Text("Replace is the only restore mode in this version. Merge is not available.")
                        .font(LifeCueTheme.captionFont)
                        .foregroundStyle(LifeCueTheme.secondaryText)
                }
            }
            .navigationTitle("Import Backup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Replace Existing Data", action: onReplace)
                }
            }
        }
    }
}

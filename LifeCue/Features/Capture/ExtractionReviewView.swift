import SwiftUI

/// Sprint 5 review + confirmation. Creates a Reminder only when the user taps Create Reminder.
struct ExtractionReviewView: View {
    @Bindable var viewModel: ExtractionReviewViewModel
    let personService: PersonService
    let contextService: ContextService
    var onCreated: (Reminder) -> Void
    var onCancel: () -> Void
    var onTryAnother: () -> Void
    var onAddManually: () -> Void

    @State private var showSuccess = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Here's what I found")
                    .font(LifeCueTheme.headlineFont)
                    .foregroundStyle(LifeCueTheme.primaryText)
                    .accessibilityAddTraits(.isHeader)

                Text("Review and edit before creating a reminder. Nothing is saved until you confirm.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)

                titleSection
                dateSection
                timeSection
                organizationSection
                noteSection

                Button {
                    viewModel.showRecognizedText = true
                } label: {
                    Label("View extracted text", systemImage: "doc.text")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Shows the text LifeCue read from your image")

                Button {
                    onTryAnother()
                } label: {
                    Label("Try Another Image", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCreating || viewModel.didCreate)

                Button {
                    onAddManually()
                } label: {
                    Label("Add Reminder Manually", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCreating || viewModel.didCreate)

                Button {
                    Task { await create() }
                } label: {
                    if viewModel.isCreating {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Create Reminder")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(LifeCueTheme.today)
                .disabled(!viewModel.canCreate)
                .accessibilityLabel("Create Reminder")

                Button("Cancel", role: .cancel, action: onCancel)
                    .frame(maxWidth: .infinity)
                    .disabled(viewModel.isCreating)
            }
            .padding(20)
            .lifeCueFormContentWidth()
        }
        .background(LifeCueTheme.background.ignoresSafeArea())
        .sheet(isPresented: $viewModel.showRecognizedText) {
            NavigationStack {
                ScrollView {
                    Text(viewModel.draft.sourceText)
                        .font(LifeCueTheme.bodyFont)
                        .foregroundStyle(LifeCueTheme.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                        .textSelection(.enabled)
                        .accessibilityLabel("Recognized text")
                }
                .background(LifeCueTheme.background.ignoresSafeArea())
                .navigationTitle("Extracted text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { viewModel.showRecognizedText = false }
                    }
                }
            }
        }
        .alert(
            "Couldn't create reminder",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(
            "Reminder created",
            isPresented: $showSuccess
        ) {
            Button("OK", role: .cancel) {
                if let reminder = viewModel.createdReminder {
                    onCreated(reminder)
                } else {
                    onCancel()
                }
            }
        } message: {
            if let warning = viewModel.scheduleWarningMessage {
                Text(warning)
            } else {
                Text("Your reminder was saved.")
            }
        }
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusHeader("Title", status: viewModel.draft.titleWasFallback ? "Fallback" : "Detected")
            TextField("Title", text: Binding(
                get: { viewModel.draft.title },
                set: { viewModel.updateTitle($0) }
            ))
            .textInputAutocapitalization(.sentences)
            .padding(12)
            .lifeCueCard()
            .accessibilityLabel("Title")
        }
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusHeader("Date", status: viewModel.dateStatusLabel)

            if case .ambiguous(_, let raw) = viewModel.draft.dateState {
                Text("This date needs confirmation\(raw.map { " (\($0))" } ?? "").")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                ForEach(Array(viewModel.ambiguousDateCandidates.enumerated()), id: \.offset) { _, candidate in
                    Button {
                        viewModel.resolveDate(to: candidate)
                    } label: {
                        Text(formatDate(candidate))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Choose date \(formatDate(candidate))")
                }
            } else {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { viewModel.pickerDate },
                        set: { viewModel.pickerDate = $0 }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
                .environment(\.timeZone, TimeZone(identifier: viewModel.draft.timeZoneIdentifier) ?? .current)
                .padding(12)
                .lifeCueCard()
                .accessibilityLabel("Date")

                if case .missing = viewModel.draft.dateState {
                    Button("Use this date") {
                        viewModel.setEventDate(from: viewModel.pickerDate)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Use this date")
                }
            }
        }
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            statusHeader("Time", status: viewModel.timeStatusLabel)

            if case .ambiguous(_, let raw) = viewModel.draft.timeState {
                Text("This time needs confirmation\(raw.map { " (\($0))" } ?? "").")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                ForEach(Array(viewModel.ambiguousTimeCandidates.enumerated()), id: \.offset) { _, candidate in
                    Button {
                        viewModel.resolveTime(to: candidate)
                    } label: {
                        Text(formatTime(candidate))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Choose time \(formatTime(candidate))")
                }
            }

            Toggle("Include time", isOn: Binding(
                get: { viewModel.includeTime },
                set: { on in
                    if on {
                        viewModel.includeTime = true
                        if viewModel.draft.timeState.isMissing {
                            viewModel.setEventTime(from: viewModel.pickerTime)
                        }
                    } else {
                        viewModel.clearTime()
                    }
                }
            ))
            .tint(LifeCueTheme.today)

            if viewModel.includeTime && !viewModel.draft.timeState.isAmbiguous {
                DatePicker(
                    "Time",
                    selection: Binding(
                        get: { viewModel.pickerTime },
                        set: { viewModel.pickerTime = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .environment(\.timeZone, TimeZone(identifier: viewModel.draft.timeZoneIdentifier) ?? .current)
                .padding(12)
                .lifeCueCard()
                .accessibilityLabel("Time")
            } else if !viewModel.includeTime {
                Text("Not detected")
                    .font(LifeCueTheme.bodyFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lifeCueCard()
            }
        }
    }

    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusHeader("Organize", status: "Optional")
            Form {
                ReminderOrganizationSection(
                    personID: Binding(
                        get: { viewModel.draft.personID },
                        set: { viewModel.selectPersonID($0) }
                    ),
                    contextID: Binding(
                        get: { viewModel.draft.contextID },
                        set: { viewModel.selectContextID($0) }
                    ),
                    personService: personService,
                    contextService: contextService
                )
            }
            .frame(minHeight: 180)
            .scrollContentBackground(.hidden)
            .lifeCueCard()
        }
    }

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            statusHeader("Note", status: viewModel.draft.note == nil ? "Not detected" : "Detected")
            TextField("Optional note", text: Binding(
                get: { viewModel.draft.note ?? "" },
                set: { viewModel.updateNote($0) }
            ), axis: .vertical)
            .lineLimit(3...6)
            .padding(12)
            .lifeCueCard()
            .accessibilityLabel("Note")
        }
    }

    private func statusHeader(_ title: String, status: String) -> some View {
        HStack {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LifeCueTheme.primaryText)
            Spacer()
            Text(status)
                .font(LifeCueTheme.captionFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
        }
    }

    private func create() async {
        let result = await viewModel.createReminder()
        if result != nil {
            showSuccess = true
        }
    }

    private func formatDate(_ comps: DateComponents) -> String {
        let formatter = DateFormatter()
        formatter.calendar = viewModel.draftCalendar
        formatter.timeZone = viewModel.draftCalendar.timeZone
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        if let date = viewModel.draftCalendar.date(from: DateComponents(
            year: comps.year, month: comps.month, day: comps.day, hour: 12
        )) {
            return formatter.string(from: date)
        }
        return "\(comps.year ?? 0)-\(comps.month ?? 0)-\(comps.day ?? 0)"
    }

    private func formatTime(_ comps: DateComponents) -> String {
        String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }
}

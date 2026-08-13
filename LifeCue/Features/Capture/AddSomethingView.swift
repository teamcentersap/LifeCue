import SwiftUI

/// Entry choices for adding something. Manual path reuses Sprint 1/2 form.
struct AddSomethingView: View {
    let reminderService: ReminderService
    let personService: PersonService
    let contextService: ContextService
    let calendarService: CalendarServing
    let ocrService: OCRServing
    let textExtractor: ReminderTextExtracting
    var onReminderSaved: () -> Void
    var onCancel: () -> Void

    private enum PresentedSheet: Identifiable {
        case manual
        case capture(ImageCaptureFlowView.Source)

        var id: String {
            switch self {
            case .manual: return "manual"
            case .capture(let source): return "capture-\(source.rawValue)"
            }
        }
    }

    @State private var presented: PresentedSheet?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Add Something")
                    .font(LifeCueTheme.headlineFont)
                    .foregroundStyle(LifeCueTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)

                choiceButton(
                    title: "Add Reminder",
                    subtitle: "Enter manually",
                    systemImage: "square.and.pencil"
                ) {
                    presented = .manual
                }

                choiceButton(
                    title: "Upload Image",
                    subtitle: "Extract information from an image",
                    systemImage: "photo.on.rectangle"
                ) {
                    presented = .capture(.library)
                }

                choiceButton(
                    title: "Take Photo",
                    subtitle: "Capture a document or note",
                    systemImage: "camera"
                ) {
                    presented = .capture(.camera)
                }

                Spacer()
            }
            .padding(20)
            .background(LifeCueTheme.background.ignoresSafeArea())
            .navigationTitle("LifeCue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .sheet(item: $presented) { item in
                switch item {
                case .manual:
                    AddReminderView(
                        service: reminderService,
                        personService: personService,
                        contextService: contextService,
                        calendarService: calendarService,
                        onSaved: {
                            presented = nil
                            onReminderSaved()
                        },
                        onCancel: { presented = nil }
                    )
                case .capture(let source):
                    ImageCaptureFlowView(
                        reminderService: reminderService,
                        personService: personService,
                        contextService: contextService,
                        ocrService: ocrService,
                        textExtractor: textExtractor,
                        initialSource: source,
                        onReminderCreated: {
                            presented = nil
                            onReminderSaved()
                        },
                        onManualFallback: {
                            presented = .manual
                        },
                        onClose: { presented = nil }
                    )
                }
            }
        }
    }

    private func choiceButton(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(LifeCueTheme.today)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(LifeCueTheme.primaryText)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(LifeCueTheme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(LifeCueTheme.secondaryText)
            }
            .padding(16)
            .lifeCueCard()
        }
        .buttonStyle(.plain)
    }
}

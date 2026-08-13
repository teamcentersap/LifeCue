import SwiftUI

/// Preview before invoking the system share sheet. Editing text does not mutate the Reminder.
struct ForwardReminderView: View {
    let reminder: Reminder
    let initialText: String
    let sharingService: ForwardSharingServing
    var onClose: () -> Void

    @State private var text: String
    @State private var isPresenting = false

    init(
        reminder: Reminder,
        initialText: String,
        sharingService: ForwardSharingServing,
        onClose: @escaping () -> Void
    ) {
        self.reminder = reminder
        self.initialText = initialText
        self.sharingService = sharingService
        self.onClose = onClose
        _text = State(initialValue: initialText)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review the message, then choose where to send it.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)

                TextEditor(text: $text)
                    .font(LifeCueTheme.bodyFont)
                    .padding(12)
                    .frame(minHeight: 220)
                    .scrollContentBackground(.hidden)
                    .background(LifeCueTheme.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .accessibilityLabel("Forward message")

                Spacer()

                Button {
                    Task { await forward() }
                } label: {
                    if isPresenting {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Forward")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(LifeCueTheme.today)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPresenting)
            }
            .padding(20)
            .background(LifeCueTheme.background.ignoresSafeArea())
            .navigationTitle("Forward Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onClose)
                }
            }
        }
    }

    private func forward() async {
        isPresenting = true
        defer { isPresenting = false }
        await sharingService.present(text: text)
        onClose()
    }
}

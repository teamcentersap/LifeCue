import SwiftUI

struct OCRResultView: View {
    let result: OCRResult
    var onTryAnother: () -> Void
    var onAddManually: () -> Void
    var onDone: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Recognized text")
                    .font(LifeCueTheme.headlineFont)
                    .foregroundStyle(LifeCueTheme.primaryText)

                Text("This text was read on your device. Reminder details will be reviewed in a later step — nothing was created yet.")
                    .font(LifeCueTheme.captionFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)

                Text(result.fullText)
                    .font(LifeCueTheme.bodyFont)
                    .foregroundStyle(LifeCueTheme.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .lifeCueCard()
                    // Accessibility: expose text to VoiceOver; do not log it.
                    .accessibilityLabel("Recognized text")

                Button(action: onTryAnother) {
                    Label("Try Another Image", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: onAddManually) {
                    Label("Add Reminder Manually", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(LifeCueTheme.today)

                Button("Done", action: onDone)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }
}

struct OCRFailureView: View {
    let message: String
    var onTryAnother: () -> Void
    var onAddManually: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "text.viewfinder")
                .font(.system(size: 40))
                .foregroundStyle(LifeCueTheme.secondaryText)
            Text(message)
                .font(LifeCueTheme.headlineFont)
                .foregroundStyle(LifeCueTheme.primaryText)
                .multilineTextAlignment(.center)
            Text("You can try another image or add a reminder manually.")
                .font(LifeCueTheme.bodyFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Button(action: onTryAnother) {
                Label("Try Another Image", systemImage: "photo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button(action: onAddManually) {
                Label("Add Reminder Manually", systemImage: "square.and.pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(LifeCueTheme.today)

            Spacer()
        }
        .padding(20)
    }
}

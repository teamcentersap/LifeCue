import SwiftUI

enum PersistenceFailurePresentation {
    static var title: String { "Couldn't Open Saved Data" }
    static var message: String {
        "LifeCue couldn't open your saved data. Your existing reminders and other data could not be loaded safely. Please restart the app and try again."
    }
}

struct PersistenceFailureView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .font(.system(size: 44))
                .foregroundStyle(LifeCueTheme.overdue)
            Text(PersistenceFailurePresentation.title)
                .font(LifeCueTheme.titleFont)
                .multilineTextAlignment(.center)
            Text(PersistenceFailurePresentation.message)
                .font(LifeCueTheme.bodyFont)
                .foregroundStyle(LifeCueTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LifeCueTheme.background.ignoresSafeArea())
    }
}

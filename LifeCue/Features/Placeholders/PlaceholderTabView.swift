import SwiftUI

struct PlaceholderTabView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: systemImage)
                    .font(.system(size: 40))
                    .foregroundStyle(LifeCueTheme.secondaryText)
                Text(title)
                    .font(LifeCueTheme.headlineFont)
                    .foregroundStyle(LifeCueTheme.primaryText)
                Text(message)
                    .font(LifeCueTheme.bodyFont)
                    .foregroundStyle(LifeCueTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .background(LifeCueTheme.background.ignoresSafeArea())
            .navigationTitle(title)
        }
    }
}

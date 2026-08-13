import SwiftUI

enum LifeCueTheme {
    static let accent = Color("AccentColor")
    static let background = Color(red: 0.96, green: 0.97, blue: 0.98)
    static let cardBackground = Color.white
    static let primaryText = Color(red: 0.12, green: 0.16, blue: 0.22)
    static let secondaryText = Color(red: 0.40, green: 0.45, blue: 0.52)
    static let overdue = Color(red: 0.75, green: 0.28, blue: 0.28)
    static let today = Color(red: 0.12, green: 0.45, blue: 0.48)
    static let upcoming = Color(red: 0.28, green: 0.40, blue: 0.58)

    static let titleFont = Font.system(.largeTitle, design: .rounded).weight(.semibold)
    static let headlineFont = Font.system(.title3, design: .rounded).weight(.semibold)
    static let bodyFont = Font.system(.body, design: .default)
    static let captionFont = Font.system(.subheadline, design: .default)
}

struct LifeCueCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(LifeCueTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, y: 2)
    }
}

extension View {
    func lifeCueCard() -> some View {
        modifier(LifeCueCardModifier())
    }
}

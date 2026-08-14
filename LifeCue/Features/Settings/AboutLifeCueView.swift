import SwiftUI

struct AboutLifeCueView: View {
    static let tagline = "Simple, local-first reminder management."

    static let requiredFeatureList = [
        "Create and manage reminders",
        "Recurring reminders",
        "People & Contexts",
        "Calendar integration",
        "Image extraction from screenshots and photos",
        "Notifications",
        "Forward reminders",
        "Backup & Restore"
    ]

    private let features = requiredFeatureList

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("LifeCue")
                        .font(LifeCueTheme.headlineFont)
                        .foregroundStyle(LifeCueTheme.primaryText)

                    LabeledContent("Version", value: LifeCueBundleInfo.marketingVersion)
                    LabeledContent("Build", value: LifeCueBundleInfo.buildNumber)

                    Text(Self.tagline)
                        .font(LifeCueTheme.bodyFont)
                        .foregroundStyle(LifeCueTheme.secondaryText)
                        .padding(.top, 4)
                }
                .padding(.vertical, 4)
            }

            Section("Features") {
                ForEach(features, id: \.self) { feature in
                    Text("• \(feature)")
                        .font(LifeCueTheme.bodyFont)
                        .foregroundStyle(LifeCueTheme.primaryText)
                }
            }
        }
        .lifeCueFormContentWidth()
        .navigationTitle("About LifeCue")
        .navigationBarTitleDisplayMode(.inline)
    }
}

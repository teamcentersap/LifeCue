import SwiftUI

struct HelpView: View {
    var body: some View {
        List {
            ForEach(HelpContent.sections) { section in
                Section(section.title) {
                    ForEach(section.questions) { item in
                        DisclosureGroup(item.question) {
                            Text(item.answer)
                                .font(LifeCueTheme.bodyFont)
                                .foregroundStyle(LifeCueTheme.secondaryText)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Help")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

struct PrivacyView: View {
    var body: some View {
        List {
            Section {
                ForEach(PrivacyContent.statements, id: \.self) { statement in
                    Text(statement)
                }
            }
        }
        .lifeCueFormContentWidth()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

struct ProUnlockView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var purchases: PurchaseManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("LifeCue Pro")
                        .font(LifeCueTheme.headlineFont)
                        .foregroundStyle(LifeCueTheme.primaryText)
                    Text("Manual reminders stay free. Unlock Pro once for photo capture, repeating reminders, Forward, and Backup.")
                        .font(LifeCueTheme.bodyFont)
                        .foregroundStyle(LifeCueTheme.secondaryText)

                    group("Free") {
                        ForEach(FeatureAccessPolicy.freeCapabilities, id: \.self) { feature($0) }
                    }

                    group("Pro includes") {
                        ForEach(FeatureAccessPolicy.proCapabilities, id: \.self) { feature($0) }
                    }

                    Button {
                        Task { await purchases.purchasePro() }
                    } label: {
                        Text(purchaseButtonTitle)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LifeCueTheme.today)
                    .disabled(purchases.isLoading || purchases.isPurchasing || purchases.hasProAccess)
                    .accessibilityIdentifier("unlockLifetimeButton")

                    Button("Restore Purchases") {
                        Task { await purchases.restore() }
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(LifeCueTheme.today)
                    .disabled(purchases.isLoading)

                    Text("Charged to your Apple ID. Restore anytime on this device. No subscription.")
                        .font(LifeCueTheme.captionFont)
                        .foregroundStyle(LifeCueTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)

                    if let error = purchases.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(LifeCueTheme.overdue)
                    } else if !purchases.statusMessage.isEmpty {
                        Text(purchases.statusMessage)
                            .font(.footnote)
                            .foregroundStyle(LifeCueTheme.secondaryText)
                    }
                }
                .padding(20)
            }
            .background(LifeCueTheme.background.ignoresSafeArea())
            .navigationTitle("Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                if purchases.proProduct == nil && !purchases.hasProAccess {
                    await purchases.loadProducts()
                }
            }
            .onChange(of: purchases.isPro) { _, unlocked in
                if unlocked { dismiss() }
            }
        }
    }

    private var purchaseButtonTitle: String {
        if purchases.hasProAccess { return "Pro Unlocked" }
        if purchases.isPurchasing { return "Purchasing..." }
        return "Unlock Lifetime"
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(LifeCueTheme.secondaryText)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .lifeCueCard()
    }

    private func feature(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LifeCueTheme.today)
            Text(text)
                .foregroundStyle(LifeCueTheme.primaryText)
            Spacer(minLength: 0)
        }
    }
}

import Foundation
import Combine
import StoreKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let proLifetimeID = AppConfig.proProductID
    private static let cacheKey = "lifecue.isProUnlocked"

    @Published private(set) var proProduct: Product?
    @Published private(set) var isPro = false
    @Published private(set) var isLoading = false
    @Published private(set) var isPurchasing = false
    @Published var lastError: String?
    @Published var statusMessage = ""

    private var updatesTask: Task<Void, Never>?

    deinit { updatesTask?.cancel() }

    var hasProAccess: Bool {
        if ProcessInfo.processInfo.arguments.contains("-ProUnlocked") { return true }
        if !AppConfig.monetizationEnabled { return true }
        return isPro
    }

    var priceText: String {
        if let proProduct { return proProduct.displayPrice }
        if isLoading { return "" }
        return ""
    }

    func start() async {
        if ProcessInfo.processInfo.arguments.contains("-ProUnlocked") || !AppConfig.monetizationEnabled {
            isPro = true
            return
        }
        isPro = UserDefaults.standard.bool(forKey: Self.cacheKey)
        updatesTask?.cancel()
        updatesTask = observeTransactions()
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        guard AppConfig.monetizationEnabled else {
            proProduct = nil
            isPro = true
            return
        }
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: [Self.proLifetimeID])
            proProduct = products.first
            if proProduct == nil {
                lastError = "Pro product is unavailable. Confirm App Store Connect IAP \(Self.proLifetimeID) is created and the Paid Apps agreement is active."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func buy() async {
        await purchasePro()
    }

    func purchasePro() async {
        guard AppConfig.monetizationEnabled else {
            isPro = true
            return
        }
        lastError = nil
        if proProduct == nil {
            await loadProducts()
        }
        guard let product = proProduct else {
            if lastError == nil {
                lastError = "Unable to load the Pro product from the App Store."
            }
            return
        }
        await purchase(product)
    }

    func restore() async {
        guard AppConfig.monetizationEnabled else {
            isPro = true
            return
        }
        lastError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            try await AppStore.sync()
            await refreshEntitlements()
            if isPro {
                statusMessage = "Restored"
            } else {
                lastError = "No previous Pro purchase found for this Apple ID."
                statusMessage = "Nothing to restore"
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func purchase(_ product: Product) async {
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try verified(verification)
                setUnlocked(true)
                await transaction.finish()
                statusMessage = "Unlocked"
                await refreshEntitlements()
            case .pending:
                lastError = "Purchase is pending approval."
                statusMessage = "Pending"
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
            statusMessage = "Purchase failed"
        }
    }

    private func refreshEntitlements() async {
        if ProcessInfo.processInfo.arguments.contains("-ProUnlocked") || !AppConfig.monetizationEnabled {
            isPro = true
            return
        }
        let previouslyUnlocked = UserDefaults.standard.bool(forKey: Self.cacheKey)
        var (unlocked, sawRevokedPro) = await computeUnlockStateFromStore()

        if !unlocked && previouslyUnlocked && !sawRevokedPro {
            try? await AppStore.sync()
            (unlocked, sawRevokedPro) = await computeUnlockStateFromStore()
        }
        if !unlocked && previouslyUnlocked && !sawRevokedPro {
            unlocked = true
        }
        setUnlocked(unlocked)
    }

    private func computeUnlockStateFromStore() async -> (unlocked: Bool, sawRevokedPro: Bool) {
        var sawRevokedPro = false
        var hasActiveEntitlement = false
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            guard transaction.productID == Self.proLifetimeID else { continue }
            if transaction.revocationDate == nil {
                hasActiveEntitlement = true
            } else {
                sawRevokedPro = true
            }
        }
        if hasActiveEntitlement {
            return (true, false)
        }
        if let latest = await Transaction.latest(for: Self.proLifetimeID),
           let transaction = try? verified(latest) {
            if transaction.revocationDate != nil {
                return (false, true)
            }
            return (true, false)
        }
        return (false, sawRevokedPro)
    }

    private func setUnlocked(_ unlocked: Bool) {
        isPro = unlocked
        UserDefaults.standard.set(unlocked, forKey: Self.cacheKey)
    }

    private func observeTransactions() -> Task<Void, Never> {
        Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                guard let transaction = try? self.verified(update) else { continue }
                await transaction.finish()
                await self.refreshEntitlements()
            }
        }
    }

    nonisolated private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified: throw StoreError.failedVerification
        }
    }

    enum StoreError: LocalizedError {
        case failedVerification
        var errorDescription: String? { "The App Store transaction could not be verified." }
    }
}

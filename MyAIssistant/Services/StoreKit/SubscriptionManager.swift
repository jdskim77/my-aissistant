import StoreKit
import SwiftUI

/// Manages StoreKit 2 subscriptions: loading products, purchasing, restoring, and listening for transactions.
@Observable @MainActor
final class SubscriptionManager {
    var products: [Product] = []
    var currentTier: SubscriptionTier = .free
    var purchaseInProgress = false
    var lastError: String?

    private nonisolated(unsafe) var transactionListener: Task<Void, Error>?

    static let allProductIDs: Set<String> = [
        AppConstants.ProductID.proMonthly,
        AppConstants.ProductID.proAnnual,
        AppConstants.ProductID.studentMonthly,
        AppConstants.ProductID.studentAnnual,
        AppConstants.ProductID.powerUserMonthly,
        AppConstants.ProductID.powerUserAnnual,
    ]

    init() {
        transactionListener = listenForTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Products

    func loadProducts() async {
        do {
            products = try await Product.products(for: Self.allProductIDs)
                .sorted { $0.price < $1.price }
        } catch {
            lastError = "Failed to load products."
        }
    }

    // MARK: - Purchase

    func purchase(_ product: Product) async -> Bool {
        purchaseInProgress = true
        defer { purchaseInProgress = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                await updateTier()
                await transaction.finish()
                return true
            case .userCancelled:
                return false
            case .pending:
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    // MARK: - Restore

    func restore() async {
        do {
            try await AppStore.sync()
            await updateTier()
        } catch {
            lastError = "Restore failed. Please try again."
        }
    }

    // MARK: - Tier Detection

    func updateTier() async {
        var detectedTier: SubscriptionTier = .free

        for await result in Transaction.currentEntitlements {
            guard let transaction = try? checkVerified(result) else { continue }

            if transaction.revocationDate == nil {
                let productID = transaction.productID
                if productID.contains("pro") {
                    detectedTier = .pro
                } else if productID.contains("student") {
                    detectedTier = .student
                } else if productID.contains("poweruser") {
                    detectedTier = .powerUser
                }
            }
        }

        currentTier = detectedTier
    }

    // MARK: - Transaction Listener

    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                guard let transaction = try? self.checkVerified(result) else { continue }
                await self.updateTier()
                await transaction.finish()
            }
        }
    }

    // MARK: - Verification

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let value):
            return value
        }
    }

    // MARK: - Product Helpers

    func product(for productID: String) -> Product? {
        products.first { $0.id == productID }
    }

    func proMonthly() -> Product? {
        product(for: AppConstants.ProductID.proMonthly)
    }

    func proAnnual() -> Product? {
        product(for: AppConstants.ProductID.proAnnual)
    }
}

// MARK: - Store Error

enum StoreError: LocalizedError {
    case verificationFailed

    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "Transaction verification failed."
        }
    }
}

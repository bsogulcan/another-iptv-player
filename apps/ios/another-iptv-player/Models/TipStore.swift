import Combine
import StoreKit
import SwiftUI

/// Consumable "tip" in-app purchases offered from Settings.
///
/// Tips unlock nothing, so there is no entitlement to track or restore: a purchase
/// only needs its transaction finished, otherwise StoreKit keeps redelivering it.
@MainActor
final class TipStore: ObservableObject {
    static let shared = TipStore()
    private init() {}

    enum Tier: String, CaseIterable, Identifiable {
        case small, medium, large

        var id: String { rawValue }

        /// Must match the product IDs in App Store Connect (and `Tips.storekit`) exactly.
        var productID: String { "dev.ogos.another_iptv_player.tip.\(rawValue)" }
    }

    enum LoadState {
        case idle, loading, loaded, failed
    }

    enum PurchaseOutcome {
        case success
        /// Ask to Buy / SCA: the transaction arrives later through `Transaction.updates`.
        case pending
        case cancelled
        case failed(String)
    }

    @Published private(set) var products: [Tier: Product] = [:]
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var purchasingTier: Tier?

    private var updatesTask: Task<Void, Never>?

    /// Call once at launch. Finishes transactions that complete outside the purchase
    /// call: approved Ask to Buy requests, and anything left unfinished by a previous
    /// run (StoreKit redelivers those right after launch).
    func startObservingTransactions() {
        guard updatesTask == nil else { return }
        updatesTask = Task {
            for await result in Transaction.updates {
                await Self.finish(result)
            }
        }
    }

    func loadProducts() async {
        guard loadState != .loading, products.count < Tier.allCases.count else { return }
        loadState = .loading
        do {
            let fetched = try await Product.products(for: Tier.allCases.map(\.productID))
            var byTier: [Tier: Product] = [:]
            for product in fetched {
                guard let tier = Tier.allCases.first(where: { $0.productID == product.id }) else { continue }
                byTier[tier] = product
            }
            products = byTier
            // StoreKit drops an unknown or not-yet-available ID instead of throwing.
            let missing = Tier.allCases.filter { byTier[$0] == nil }.map(\.productID)
            if !missing.isEmpty {
                Log.error("TipStore", "App Store returned no product for: \(missing.joined(separator: ", "))")
            }
            loadState = byTier.isEmpty ? .failed : .loaded
        } catch {
            Log.error("TipStore", "Product request failed: \(error)")
            loadState = .failed
        }
    }

    /// `purchase` is the SwiftUI environment action, which ties the payment sheet to
    /// the scene of the calling view.
    func purchase(_ tier: Tier, using purchase: PurchaseAction) async -> PurchaseOutcome {
        guard purchasingTier == nil, let product = products[tier] else { return .cancelled }
        purchasingTier = tier
        defer { purchasingTier = nil }
        do {
            switch try await purchase(product) {
            case .success(let verification):
                if await Self.finish(verification) { return .success }
                return .failed(L("common.unknown_error"))
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .cancelled
            }
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// Only acknowledge verified tips owned by this store. Other product types
    /// must remain available to their own transaction handlers.
    @discardableResult
    private static func finish(_ result: VerificationResult<StoreKit.Transaction>) async -> Bool {
        guard case .verified(let transaction) = result else {
            Log.error("TipStore", "Transaction verification failed")
            return false
        }
        guard Tier.allCases.contains(where: { $0.productID == transaction.productID }),
              transaction.productType == .consumable,
              transaction.revocationDate == nil else { return false }
        await transaction.finish()
        return true
    }
}

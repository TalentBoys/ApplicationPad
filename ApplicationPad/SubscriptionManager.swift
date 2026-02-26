//
//  SubscriptionManager.swift
//  ApplicationPad
//
//  Manages subscription state using StoreKit 2
//

import Foundation
import StoreKit
import Combine

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    static let subscriptionGroupID = "21949029"
    static let productID = "3monthtrial"

    @Published var isSubscribed = false
    @Published var product: Product?
    @Published var subscriptionStatus: Product.SubscriptionInfo.Status?

    private var transactionListener: Task<Void, Never>?

    init() {
        transactionListener = observeTransactions()
    }

    deinit {
        transactionListener?.cancel()
    }

    // MARK: - Load Product

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.productID])
            product = products.first
        } catch {
            print("Failed to load products: \(error)")
        }
    }

    // MARK: - Check Subscription

    func checkSubscription() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            if transaction.productID == Self.productID {
                isSubscribed = transaction.revocationDate == nil
                return
            }
        }
        // No entitlement found
        isSubscribed = false
    }

    // MARK: - Observe Transactions

    private func observeTransactions() -> Task<Void, Never> {
        Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await self?.checkSubscription()
            }
        }
    }

    // MARK: - Purchase

    func purchase() async throws {
        guard let product else {
            print("Product not loaded")
            return
        }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else { return }
            await transaction.finish()
            await checkSubscription()
        case .userCancelled:
            break
        case .pending:
            break
        @unknown default:
            break
        }
    }

    // MARK: - Restore

    func restore() async {
        try? await AppStore.sync()
        await checkSubscription()
    }
}

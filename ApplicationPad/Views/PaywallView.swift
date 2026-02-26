//
//  PaywallView.swift
//  ApplicationPad
//
//  Subscription paywall using StoreKit 2 SubscriptionStoreView
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @ObservedObject var subscriptionManager = SubscriptionManager.shared

    var body: some View {
        SubscriptionStoreView(groupID: SubscriptionManager.subscriptionGroupID) {
            VStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)

                Text("ApplicationPad")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("A better app launcher for macOS")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                statusBadge
            }
            .padding(.vertical, 16)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.hidden, for: .cancellation)
        .frame(width: 500, height: 680)
        .task {
            await subscriptionManager.loadProduct()
            await subscriptionManager.checkSubscription()
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if subscriptionManager.isSubscribed {
            Label("Active", systemImage: "checkmark.seal.fill")
                .font(.callout)
                .foregroundStyle(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.green.opacity(0.1), in: Capsule())
        } else {
            Label("Not Subscribed", systemImage: "xmark.circle")
                .font(.callout)
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.red.opacity(0.1), in: Capsule())
        }
    }
}

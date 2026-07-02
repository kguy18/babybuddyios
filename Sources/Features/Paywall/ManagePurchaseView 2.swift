import SwiftUI

/// Shows the current Pro status and lets the customer restore or manage their subscription.
///
/// **Not presented anywhere yet.** Placeholder for a future Settings row. The "Manage Subscription"
/// link opens Apple's system subscription management; restore uses ``PurchaseManager``.
struct ManagePurchaseView: View {
    @Environment(PurchaseManager.self) private var purchases

    @State private var isRestoring = false

    private let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        List {
            Section("Status") {
                HStack {
                    Text("Baby Buddy Pro")
                    Spacer()
                    if purchases.hasPremium {
                        Label("Active", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(BBColor.success)
                            .labelStyle(.titleAndIcon)
                    } else {
                        Text("Not subscribed")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                Button {
                    Task {
                        isRestoring = true
                        await purchases.restore()
                        isRestoring = false
                    }
                } label: {
                    HStack {
                        Text("Restore Purchases")
                        Spacer()
                        if isRestoring { ProgressView() }
                    }
                }
                .disabled(!purchases.isConfigured || isRestoring)

                Link(destination: manageSubscriptionsURL) {
                    Text("Manage Subscription")
                }
            } footer: {
                if !purchases.isConfigured {
                    Text("In-app purchases are not available in this build.")
                }
            }
        }
        .navigationTitle("Manage Purchase")
        .navigationBarTitleDisplayMode(.inline)
    }
}

import SwiftUI

/// Shows the current Premium status and lets the customer restore their purchase.
///
/// **Not presented anywhere yet.** Placeholder for a future Settings row. Premium is a one-time
/// non-consumable purchase, so there is nothing to "manage" or cancel — Restore is the only action.
/// Restore uses ``PurchaseManager``.
struct ManagePurchaseView: View {
    @Environment(PurchaseManager.self) private var purchases

    @State private var isRestoring = false

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
                        Text("Not purchased")
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

import SwiftUI
#if canImport(RevenueCatUI)
import RevenueCatUI
#endif

/// The upgrade paywall: what Pro unlocks, why to upgrade, and the purchase / restore actions.
///
/// This view holds **no business logic** — it renders state from ``PurchaseManager`` and routes the
/// two actions (purchase, restore) back to it. Feature copy comes from the ``FeatureAccess`` /
/// ``PremiumFeature`` catalog. When the optional `RevenueCatUI` package is linked, RevenueCat's
/// prebuilt `PaywallView` is used instead of the hand-built layout below.
struct PremiumScreen: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        #if canImport(RevenueCatUI)
        // Prebuilt, remotely-configured paywall — used automatically when RevenueCatUI is available.
        PaywallView()
            .onAppear { Analytics.paywallViewed() }
        #else
        customPaywall
            .onAppear { Analytics.paywallViewed() }
        #endif
    }

    // MARK: - Hand-built paywall

    private var customPaywall: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    header
                    featuresSection
                    whyUpgradeSection
                    purchaseSection
                    legalFooter
                }
                .padding(20)
            }
            .background(BBColor.surface.ignoresSafeArea())
            .navigationTitle("Baby Buddy Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "star.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(BBColor.brand)
                .accessibilityHidden(true)
            Text("Unlock everything")
                .font(.title.bold())
            Text("Track every activity, see deeper insights, and support ongoing development.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    // MARK: Premium Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Premium Features")
            BBCard {
                VStack(spacing: 0) {
                    ForEach(Array(FeatureAccess.premiumFeatures.enumerated()), id: \.element) { index, feature in
                        if index > 0 { Divider().foregroundStyle(BBColor.divider) }
                        featureRow(feature)
                            .padding(.vertical, 10)
                    }
                }
            }
        }
    }

    private func featureRow(_ feature: PremiumFeature) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: feature.systemImage)
                .font(.title3)
                .foregroundStyle(BBColor.brand)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title).font(.headline)
                Text(feature.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: Why Upgrade

    private var whyUpgradeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Why Upgrade")
            BBCard {
                VStack(alignment: .leading, spacing: 14) {
                    reason("heart.fill", "Support development",
                           "Baby Buddy is built and maintained by a small team. Pro keeps it going.")
                    reason("lock.shield.fill", "Private by design",
                           "Your family's data stays yours — Pro adds features, not tracking.")
                    reason("infinity", "Everything, forever-improving",
                           "One upgrade unlocks every premium feature, including future additions.")
                }
            }
        }
    }

    private func reason(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(BBColor.brandAccent)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Purchase / Restore

    private var purchaseSection: some View {
        VStack(spacing: 12) {
            if purchases.hasPremium {
                Label("You have Baby Buddy Pro", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(BBColor.success)
            } else {
                Button {
                    Task { await purchases.purchase() }
                } label: {
                    if purchases.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(.bbPrimary)
                .disabled(!purchases.isConfigured || purchases.isLoading)

                Button("Restore Purchases") {
                    Task { await purchases.restore() }
                }
                .font(.subheadline)
                .disabled(!purchases.isConfigured || purchases.isLoading)

                if let message = purchases.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(BBColor.danger)
                        .multilineTextAlignment(.center)
                }

                if !purchases.isConfigured {
                    Text("Purchases aren't available in this build.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Legal

    private var legalFooter: some View {
        HStack(spacing: 6) {
            Link("Privacy Policy", destination: PremiumLinks.privacyPolicy)
            Text("•").foregroundStyle(.tertiary)
            Link("Terms of Service", destination: PremiumLinks.termsOfService)
        }
        .font(.footnote)
        .tint(BBColor.brandAccent)
        .padding(.top, 4)
    }
}

#Preview {
    PremiumScreen()
        .environment(PurchaseManager())
}

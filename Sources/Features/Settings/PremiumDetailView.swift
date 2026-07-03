import SwiftUI

/// Detail screen reached by tapping "Baby Buddy Pro" in Settings. Holds the premium actions —
/// start trial, upgrade, restore, manage, and legal links — so the Settings row itself shows only
/// the current status.
///
/// No business logic: it reads ``PurchaseManager`` / ``TrialManager`` and routes actions back to
/// them (Start Free Trial pops the ``TrialOfferView`` modal; Upgrade opens ``PremiumScreen``). The
/// conditional rows mirror the tier rules — Start Free Trial only when no trial was ever started,
/// Upgrade only when Pro isn't owned.
struct PremiumDetailView: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(TrialManager.self) private var trial
    @Environment(\.openURL) private var openURL

    @State private var showPaywall = false
    @State private var showTrialOffer = false
    @State private var isRestoring = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                card {
                    if !purchases.hasPremium && !trial.hasStartedTrial {
                        actionRow(symbol: "gift.fill", tint: BBColor.success, title: "Start Free Trial") {
                            showTrialOffer = true
                        }
                        rowDivider
                    }

                    if !purchases.hasPremium {
                        actionRow(symbol: "sparkles", tint: BBColor.brand, title: "Upgrade") {
                            Analytics.upgradePressed()
                            showPaywall = true
                        }
                        rowDivider
                    }

                    restoreRow

                    rowDivider
                    NavigationLink { ManagePurchaseView() } label: {
                        SettingsRow(symbol: "creditcard", tint: BBColor.brandAccent, title: "Manage Purchases") {
                            disclosure
                        }
                    }
                    .buttonStyle(.plain)

                    rowDivider
                    linkRow(symbol: "hand.raised", title: "Privacy Policy", url: PremiumLinks.privacyPolicy)

                    rowDivider
                    linkRow(symbol: "doc.text", title: "Terms of Service", url: PremiumLinks.termsOfService)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(BBColor.surface)
        .navigationTitle("Baby Buddy Pro")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPaywall) { PremiumScreen() }
        .sheet(isPresented: $showTrialOffer) {
            TrialOfferView().presentationDetents([.medium])
        }
    }

    // MARK: Rows

    private var restoreRow: some View {
        Button {
            Task { isRestoring = true; await purchases.restore(); isRestoring = false }
        } label: {
            SettingsRow(symbol: "arrow.clockwise", tint: BBColor.info, title: "Restore Purchases") {
                if isRestoring { ProgressView().controlSize(.small) }
            }
        }
        .buttonStyle(.plain)
        .disabled(isRestoring)
    }

    private func actionRow(symbol: String, tint: Color, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            SettingsRow(symbol: symbol, tint: tint, title: title) { disclosure }
        }
        .buttonStyle(.plain)
    }

    private func linkRow(symbol: String, title: String, url: URL) -> some View {
        Button { openURL(url) } label: {
            SettingsRow(symbol: symbol, tint: BBColor.note, title: title) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Layout helpers

    private func card<V: View>(@ViewBuilder _ content: @escaping () -> V) -> some View {
        BBCard(cornerRadius: BBRadius.tile, padding: 0) {
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 15)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(BBColor.divider).frame(height: 0.5)
    }

    private var disclosure: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
    }
}

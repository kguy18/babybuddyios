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
                proHeader

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

    // MARK: Upsell header

    /// A brand banner (crown + pitch + state pill) over three value bullets, sitting above the
    /// actions. Adapts its copy/pill to whether the customer has Pro, a trial, or neither.
    private var proHeader: some View {
        VStack(spacing: 12) {
            banner
            bulletsCard
        }
    }

    private var banner: some View {
        HStack(spacing: 14) {
            Image(systemName: "crown.fill")
                .font(.system(size: 26))
                .foregroundStyle(BBColor.stop)
                .frame(width: 46, height: 46)
                .background(.white.opacity(0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Baby Buddy Pro")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(bannerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 8)
            bannerPill
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BBColor.brand, in: RoundedRectangle(cornerRadius: BBRadius.tile, style: .continuous))
    }

    @ViewBuilder private var bannerPill: some View {
        if hasPro {
            Label("Active", systemImage: "checkmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BBColor.brandAccent)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(.white, in: Capsule())
        } else if trialAvailable {
            Button {
                showTrialOffer = true
            } label: {
                Text("14-day trial")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: UIColor(hex: "5C4300")))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color(uiColor: UIColor(hex: "FFD873")), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start 14-day free trial")
        }
    }

    private var bulletsCard: some View {
        BBCard(cornerRadius: BBRadius.tile) {
            VStack(alignment: .leading, spacing: 11) {
                bullet("Track feeding, sleep, pumping, and tummy time")
                bullet("Live timers, notes, and detailed insights")
                bullet("Support ongoing development")
            }
        }
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BBColor.success)
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private var hasPro: Bool { purchases.hasPremium || trial.isTrialActive }
    private var trialAvailable: Bool { !purchases.hasPremium && !trial.hasStartedTrial }
    private var bannerSubtitle: String {
        hasPro ? "You have full access" : "Unlock every premium feature"
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

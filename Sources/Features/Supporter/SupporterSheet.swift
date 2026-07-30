import SwiftUI

/// Shared legal links shown on the supporter sheet. Replace these with the hosted policy URLs
/// before shipping.
enum SupporterLinks {
    static let privacyPolicy = URL(string: "https://github.com/kguy18/babybuddyios/blob/main/PRIVACY.md")!
    static let termsOfService = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// The app's one purchase surface — a tip jar, nothing more.
///
/// Every feature is free and stays free; this sheet only asks for an optional one-time tip, in one
/// of three amounts, and thanks the people who leave one. It is deliberately the single destination
/// for every "support" entry point (Settings, `babybuddy://supporter`, and the nudges later), so
/// there is exactly one purchase flow to build, test, and submit for review.
///
/// Holds **no business logic**: it renders ``PurchaseManager`` state and routes tip / restore back
/// to it. Three states, in priority order — purchases unavailable (open-source or demo builds),
/// supporter (thank-you, with a quiet path to tip again), and the amounts.
struct SupporterSheet: View {
    /// Which entry point opened the sheet. Carried onto every signal from here on — including the
    /// tip itself — so a purchase is attributed to the door it came through rather than needing a
    /// separate conversion event. See ``Analytics/SupporterSource``.
    let source: Analytics.SupporterSource

    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    /// The amount the customer has actually tapped. `nil` until they do — the effective selection is
    /// then ``selectedTier``, which follows the offering's preselected default as it loads. Holding
    /// "untouched" as its own value is what lets a late-arriving offering set the default without
    /// ever overwriting a choice someone already made.
    @State private var selection: TipTier?
    /// Supporters land on the thank-you; the amounts appear only if they ask to tip again.
    @State private var showingAmounts = false

    var body: some View {
        FittedSheet {
            content
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 30)
        }
        .task {
            // An offering fetch that failed at launch would otherwise be sticky for the whole session,
            // leaving the sheet with nothing to offer until the app is relaunched. Retrying as it opens
            // lets it heal itself; a no-op once the tips are in hand, so the normal case is untouched.
            if purchases.tips.isEmpty { await purchases.refresh() }
            // Reported after that retry rather than in `onAppear`, so `state` describes what the sheet
            // settled on instead of what it looked like mid-fetch — otherwise every open on a cold
            // launch would report `unavailableNoTips` and the signal would mean nothing. The retry is
            // a no-op in the normal case, so this is still effectively immediate.
            Analytics.supporterSheetViewed(source: source, state: analyticsState,
                                           offering: purchases.offeringIdentifier)
        }
    }

    // MARK: - Remote configuration

    /// The serving offering's tuning, or the compiled defaults. See ``SupporterRemoteConfig``.
    private var config: SupporterRemoteConfig { purchases.supporterConfig }

    /// The amount the tip button will buy: whatever was tapped, else the configured default.
    private var selectedTier: TipTier { selection ?? config.defaultTier }

    /// The copy this sheet speaks in — a compiled variant chosen by name; see ``SupporterCopy``.
    private var copy: SupporterCopy { SupporterCopy(variant: config.copyVariant) }

    /// What the sheet actually has to show, for the funnel.
    ///
    /// A supporter reports ``Analytics/SupporterSheetState/thankYou`` even if the offering is broken:
    /// no ask is being made of them, so the two unavailable states are reserved for the population
    /// they matter for — people who came here to tip and found nothing to buy.
    private var analyticsState: Analytics.SupporterSheetState {
        if purchases.isSupporter { return .thankYou }
        if !purchases.isConfigured { return .unavailableUnconfigured }
        return purchases.tips.isEmpty ? .unavailableNoTips : .ask
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            hero

            Text(purchases.isSupporter ? SupporterCopy.thankYouTitle : copy.askTitle)
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 14)

            Text(purchases.isSupporter ? SupporterCopy.thankYouBody : copy.askBody)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 7)

            if showsAmounts {
                amounts
                tipButton
            } else if canTip {
                // A supporter has already tipped, so the amounts stay folded away behind a quieter
                // button — the thank-you is the point of the screen for them, not another ask.
                tipAgainButton
            } else {
                unavailableNotice
            }

            errorMessage
            quietButton
            if showsAmounts { fineprint }
            footer
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// Whether there is actually something to buy. Being configured isn't enough: the offering has to
    /// have yielded tips. A configured build with no tips — a dashboard offering that carries no
    /// products, or a first fetch that failed — must not show amounts, because tipping one would find
    /// no package and silently do nothing.
    private var canTip: Bool {
        purchases.isConfigured && !purchases.tips.isEmpty
    }

    /// Whether the amounts are on screen: there has to be something to sell, and a supporter has to
    /// have asked to tip again.
    private var showsAmounts: Bool {
        canTip && (!purchases.isSupporter || showingAmounts)
    }

    /// A heart in the brand tint — the same tinted-glyph-tile motif the rest of the app uses.
    private var hero: some View {
        SupporterBadge()
    }

    // MARK: Tips

    private var amounts: some View {
        HStack(spacing: 9) {
            ForEach(TipTier.allCases) { tier in
                TipTile(tier: tier, price: price(for: tier), isSelected: selectedTier == tier) {
                    selection = tier
                }
            }
        }
        .padding(.top, 18)
    }

    private var tipButton: some View {
        Button {
            Task {
                await purchases.purchase(tier: selectedTier, source: source)
                // Back to the thank-you: either the tip landed, or it was cancelled and the ask has
                // been made once already.
                showingAmounts = false
            }
        } label: {
            if purchases.isLoading {
                ProgressView().tint(.white)
            } else {
                Text("Tip \(price(for: selectedTier))")
            }
        }
        .buttonStyle(.bbPrimary)
        .disabled(purchases.isLoading)
        .padding(.top, 20)
    }

    private var tipAgainButton: some View {
        Button("Tip again") {
            Analytics.supporterTipAgainPressed()
            withAnimation(.snappy(duration: 0.2)) { showingAmounts = true }
        }
        .buttonStyle(.bbTinted)
        .padding(.top, 20)
    }

    private var fineprint: some View {
        Text("One-time tip · not a subscription — supports this app, not the Baby Buddy open-source project.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .padding(.top, 2)
    }

    /// Why there are no amounts. Two different situations, and the distinction matters: a build
    /// without a RevenueCat key (the public repository, forks, demo mode) will never sell anything,
    /// whereas a configured build whose tips didn't load may well work on the next try.
    private var unavailableNotice: some View {
        Text(purchases.isConfigured
             ? "Tips aren't available right now — please try again later."
             : "Purchases aren't available in this build.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.top, 20)
    }

    @ViewBuilder private var errorMessage: some View {
        if let message = purchases.errorMessage {
            Text(message)
                .font(.footnote)
                .foregroundStyle(BBColor.danger)
                .padding(.top, 14)
        }
    }

    // MARK: Dismiss & footer

    private var quietButton: some View {
        Button { dismiss() } label: {
            Text(purchases.isSupporter ? "Done" : "Maybe later")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Restore plus the legal links App Review expects alongside a purchase.
    private var footer: some View {
        VStack(spacing: 12) {
            Button("Restore Purchases") {
                Task { await purchases.restore() }
            }
            .font(.subheadline)
            .tint(BBColor.brandAccent)
            .disabled(!purchases.isConfigured || purchases.isLoading)

            HStack(spacing: 6) {
                Link("Privacy Policy", destination: SupporterLinks.privacyPolicy)
                Text("•").foregroundStyle(.tertiary)
                Link("Terms of Service", destination: SupporterLinks.termsOfService)
            }
            .font(.footnote)
            .tint(BBColor.brandAccent)
        }
        .padding(.top, 14)
    }

    /// The store's own currency-localized price, falling back to the US list price only when no
    /// offering has loaded (a build without purchases, or before the fetch lands).
    private func price(for tier: TipTier) -> String {
        purchases.tips.first { $0.tier == tier }?.localizedPrice ?? tier.fallbackPrice
    }
}

// MARK: - Copy

/// The supporter sheet's headline and body, per ``SupporterCopyVariant``.
///
/// Every string here is compiled in. The remote config selects a variant *by name* and can never
/// supply text — see ``SupporterRemoteConfig`` for why. Only the ask varies: the thank-you is what
/// the app says to someone who has already paid, and there is nothing to test about it.
struct SupporterCopy {
    let askTitle: String
    let askBody: String

    static let thankYouTitle = "You're a Supporter ❤️"
    static let thankYouBody = "Thank you for chipping in — it keeps Baby Buddy Companion free for everyone."

    init(variant: SupporterCopyVariant) {
        switch variant {
        case .standard:
            askTitle = "Support Baby Buddy Companion"
            askBody = "The whole app is free, and stays that way. A one-time tip supports development — thank you either way."
        case .warm:
            askTitle = "Keep Baby Buddy Companion going"
            askBody = "Every feature is free, for everyone, and always will be. If the app has earned a place in your day, a one-time tip helps it keep growing."
        }
    }
}

// MARK: - Amount tile

/// One amount in the tip row: the price over its tier name. Selection follows the app's pick-tile
/// grammar (``ActivityPickTile``) — a 2pt ring plus a check badge — in brand blue rather than an
/// activity color, since a tip isn't one of the record kinds.
private struct TipTile: View {
    let tier: TipTier
    let price: String
    let isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(price)
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(tier.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .padding(.horizontal, 6)
            .background(isSelected ? BBColor.brandTint : BBColor.nested,
                        in: RoundedRectangle(cornerRadius: BBRadius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BBRadius.control, style: .continuous)
                    .strokeBorder(BBColor.primary, lineWidth: isSelected ? 2 : 0)
            }
            .overlay(alignment: .topTrailing) { badge }
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isSelected)
        .accessibilityLabel("\(tier.label), \(price)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// Overhangs the tile's corner, with a card-colored rim so it reads against the ring.
    private var badge: some View {
        ZStack {
            Circle().fill(BBColor.primary)
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: 20, height: 20)
        .overlay { Circle().strokeBorder(BBColor.card, lineWidth: 2) }
        .offset(x: 7, y: -7)
        .opacity(isSelected ? 1 : 0)
    }
}

private extension TipTier {
    /// What this amount is called on its tile.
    var label: String {
        switch self {
        case .small: return "Kind"
        case .medium: return "Generous"
        case .large: return "Amazing"
        }
    }

    /// The US list price, shown only until the store's own localized price arrives.
    var fallbackPrice: String {
        switch self {
        case .small: return "$4.99"
        case .medium: return "$9.99"
        case .large: return "$19.99"
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SupporterSheet(source: .settings)
                .environment(PurchaseManager())
        }
}

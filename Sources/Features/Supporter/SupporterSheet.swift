import SwiftUI

/// Shared legal links shown on the supporter sheet. Replace these with the hosted policy URLs
/// before shipping.
enum SupporterLinks {
    static let privacyPolicy = URL(string: "https://github.com/kguy18/babybuddyios/blob/main/PRIVACY.md")!
    static let termsOfService = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// The app's one purchase surface — a tip jar, not a paywall.
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
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    /// Preselected at the middle amount, per the design.
    @State private var selection: TipTier = .medium
    /// Supporters land on the thank-you; the amounts appear only if they ask to tip again.
    @State private var showingAmounts = false
    /// The laid-out content height, so the sheet is exactly as tall as what's in it.
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content
                .padding(.horizontal, 22)
                .padding(.top, 10)
                .padding(.bottom, 30)
                .background { heightReader }
        }
        // Content taller than the detent (large Dynamic Type) scrolls; anything shorter doesn't.
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(BBColor.card)
        .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }
        .onAppear { Analytics.supporterSheetViewed() }
    }

    /// Fit the sheet to its content. `.medium` covers the first frame only, before the measurement
    /// lands; the system clamps an over-tall content height to the maximum sheet height for us.
    private var detents: Set<PresentationDetent> {
        contentHeight > 0 ? [.height(contentHeight)] : [.medium]
    }

    private var heightReader: some View {
        GeometryReader { proxy in
            Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
        }
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            hero

            Text(purchases.isSupporter ? "You're a Supporter ❤️" : "Support Baby Buddy Companion")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 14)

            Text(purchases.isSupporter
                 ? "Thank you for chipping in — it keeps Baby Buddy Companion free for everyone."
                 : "The whole app is free, and stays that way. A one-time tip supports development — thank you either way.")
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
        RoundedRectangle(cornerRadius: BBRadius.tile, style: .continuous)
            .fill(BBColor.brandTint)
            .frame(width: 54, height: 54)
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(BBColor.brandAccent)
            }
            .accessibilityHidden(true)
    }

    // MARK: Tips

    private var amounts: some View {
        HStack(spacing: 9) {
            ForEach(TipTier.allCases) { tier in
                TipTile(tier: tier, price: price(for: tier), isSelected: selection == tier) {
                    selection = tier
                }
            }
        }
        .padding(.top, 18)
    }

    private var tipButton: some View {
        Button {
            Task {
                await purchases.purchase(tier: selection)
                // Back to the thank-you: either the tip landed, or it was cancelled and the ask has
                // been made once already.
                showingAmounts = false
            }
        } label: {
            if purchases.isLoading {
                ProgressView().tint(.white)
            } else {
                Text("Tip \(price(for: selection))")
            }
        }
        .buttonStyle(.bbPrimary)
        .disabled(purchases.isLoading)
        .padding(.top, 20)
    }

    private var tipAgainButton: some View {
        Button("Tip again") {
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

// MARK: - Height measurement

/// Carries the content's laid-out height up to the sheet, so the detent can match it.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SupporterSheet()
                .environment(PurchaseManager())
        }
}

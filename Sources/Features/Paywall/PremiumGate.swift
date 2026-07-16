import SwiftUI

// The reusable building blocks for gating premium features. Locked features are never hidden — they
// are shown disabled with an explanation and an upgrade path to ``PremiumScreen``. All gating UI is
// centralized here so no screen re-implements the "what you tried / why it's locked / what Premium
// unlocks" treatment.

/// Shared legal links used by the paywall and the Settings premium section. Replace these with the
/// hosted policy URLs before shipping.
enum PremiumLinks {
    static let privacyPolicy = URL(string: "https://github.com/kguy18/babybuddyios/blob/main/PRIVACY.md")!
    static let termsOfService = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// A button that opens the paywall. Centralizes the ``PremiumScreen`` presentation so no call site
/// repeats the sheet plumbing.
struct UpgradeButton<Label: View>: View {
    @ViewBuilder var label: () -> Label
    @State private var showPaywall = false

    var body: some View {
        Button(action: { Analytics.upgradePressed(); showPaywall = true }, label: label)
            .sheet(isPresented: $showPaywall) { PremiumScreen() }
    }
}

extension UpgradeButton where Label == Text {
    /// Convenience for a plain-text upgrade button (e.g. `UpgradeButton().buttonStyle(.bbPrimary)`).
    init(_ title: String = "Upgrade to Premium") { self.init { Text(title) } }
}

/// Full, centered "this is locked" panel used to replace a premium screen or form the user cannot
/// yet use. Explains the feature, why it's locked, and what Premium unlocks, then offers the upgrade.
///
/// Deliberately contains no `NavigationStack` of its own so it can be dropped inside an existing one
/// (e.g. the editor) as well as stand alone (e.g. a tab).
struct PremiumLockView: View {
    let feature: PremiumFeature

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 40))
                .foregroundStyle(BBColor.brand)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                // What the user attempted.
                Text(feature.title)
                    .font(.title3.bold())
                // Why it's locked.
                Text("This is a Baby Buddy Premium feature.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // What this specific feature does…
            Text(feature.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // …and what Premium unlocks overall.
            Text("Baby Buddy Premium unlocks every premium feature — sleep, pumping, timers, trends, notes, and more.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            UpgradeButton()
                .buttonStyle(.bbPrimary)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .onAppear { Analytics.lockedFeatureViewed(feature: feature.rawValue) }
    }
}

/// Compact inline banner used where the surrounding content stays visible (e.g. viewing an existing
/// entry) but a premium action is disabled. Explains the limitation and offers the upgrade.
struct PremiumLockBanner: View {
    var message: String = "Editing entries is a Baby Buddy Premium feature. You can still view this entry — upgrade to make changes."

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.fill")
                .foregroundStyle(BBColor.brand)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                UpgradeButton("Upgrade to Premium")
                    .font(.subheadline.weight(.semibold))
                    .tint(BBColor.brandAccent)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BBColor.brandTint, in: RoundedRectangle(cornerRadius: BBRadius.row, style: .continuous))
        .accessibilityElement(children: .combine)
        .onAppear { Analytics.lockedFeatureViewed(feature: PremiumFeature.timelineEditing.rawValue) }
    }
}

/// Wraps a premium screen or section: shows `content` when the feature is unlocked, otherwise shows
/// ``PremiumLockView``. Reads entitlement + trial state from the environment so call sites don't
/// repeat the access check.
struct PremiumGate<Content: View>: View {
    let feature: PremiumFeature
    @ViewBuilder var content: () -> Content

    @Environment(PurchaseManager.self) private var purchases
    @Environment(TrialManager.self) private var trial

    private var isUnlocked: Bool {
        FeatureAccess.isUnlocked(feature: feature,
                                 hasPremium: purchases.hasPremium,
                                 isTrial: trial.isTrialActive)
    }

    var body: some View {
        if isUnlocked {
            content()
        } else {
            PremiumLockView(feature: feature)
        }
    }
}

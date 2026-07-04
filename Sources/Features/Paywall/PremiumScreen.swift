import SwiftUI

/// The upgrade paywall — a single, non-scrolling screen: a crown hero, a colorful grid of the
/// premium activities, and a one-time "Buy Premium" purchase.
///
/// Holds **no business logic and no RevenueCat coupling** — it renders state from ``PurchaseManager``
/// and routes purchase / restore back to it. The optional RevenueCat-prebuilt paywall is vended by
/// ``RevenueCatPaywallView`` (the sole UI boundary that touches RevenueCatUI); this view is the
/// hand-built fallback.
struct PremiumScreen: View {
    @Environment(PurchaseManager.self) private var purchases
    @Environment(\.dismiss) private var dismiss

    private struct Chip: Identifiable {
        let kind: EntityKind
        let label: String
        var id: String { label }
    }

    /// Uses the app's own activity glyphs + colors (via ``EntityKind``) so the chips match the
    /// dashboard, timeline, and editor exactly.
    private let chips: [Chip] = [
        Chip(kind: .feeding, label: "Feeding"),
        Chip(kind: .sleep, label: "Sleep"),
        Chip(kind: .pumping, label: "Pumping"),
        Chip(kind: .timer, label: "Timers"),
        Chip(kind: .note, label: "Notes"),
        Chip(kind: .weight, label: "Growth")
    ]

    var body: some View {
        RevenueCatPaywallView { customPaywall }
            .onAppear { Analytics.paywallViewed() }
    }

    // MARK: - Hand-built paywall (single screen, no scrolling)

    private var customPaywall: some View {
        VStack(spacing: 0) {
            closeBar

            Spacer(minLength: 12)

            VStack(spacing: 0) {
                hero
                chipGrid
                    .padding(.horizontal, 20)
                    .padding(.top, 26)
                bulletList
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                footer
                    .padding(.horizontal, 20)
                    .padding(.top, 30)
            }

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BBColor.card.ignoresSafeArea())
    }

    private var closeBar: some View {
        HStack {
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(BBColor.controlFill, in: Circle())
            }
            .accessibilityLabel("Close")
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(BBColor.stop.opacity(0.18)).frame(width: 88, height: 88)
                Image(systemName: "crown.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(BBColor.stop)
            }
            .accessibilityHidden(true)

            Text("Unlock everything")
                .font(.title.bold())
            Text("Track every activity, see the trends, and support the app.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Feature chips

    private var chipGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(chips) { chipView($0) }
        }
    }

    private func chipView(_ chip: Chip) -> some View {
        let color = BBColor.activity(chip.kind)
        return HStack(spacing: 9) {
            chip.kind.icon(19)
                .frame(width: 22)
            Text(chip.label)
                .font(.subheadline.weight(.medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Benefit bullets

    private var bulletList: some View {
        VStack(alignment: .leading, spacing: 12) {
            bullet("Track feeding, sleep, pumping, and tummy time")
            bullet("Live timers, notes, and detailed insights")
            bullet("Support ongoing development")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bullet(_ text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
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

    // MARK: Price / purchase / legal

    private var footer: some View {
        VStack(spacing: 14) {
            if purchases.hasPremium {
                Label("You have Premium", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(BBColor.success)
            } else {
                priceBlock
                buyButton

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

            restoreButton
            legalFooter
        }
    }

    private var priceBlock: some View {
        VStack(spacing: 2) {
            Text("$9.99")
                .font(.system(size: 30, weight: .bold))
            Text("Unlock forever · one-time purchase")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var buyButton: some View {
        Button {
            Task { await purchases.purchase() }
        } label: {
            if purchases.isLoading {
                ProgressView().tint(.white)
            } else {
                Text("Buy Premium")
            }
        }
        .buttonStyle(.bbPrimary)
        .disabled(!purchases.isConfigured || purchases.isLoading)
    }

    private var restoreButton: some View {
        Button("Restore Purchases") {
            Task { await purchases.restore() }
        }
        .font(.subheadline)
        .tint(BBColor.brandAccent)
        .disabled(!purchases.isConfigured || purchases.isLoading)
    }

    private var legalFooter: some View {
        HStack(spacing: 6) {
            Link("Privacy Policy", destination: PremiumLinks.privacyPolicy)
            Text("•").foregroundStyle(.tertiary)
            Link("Terms of Service", destination: PremiumLinks.termsOfService)
        }
        .font(.footnote)
        .tint(BBColor.brandAccent)
    }
}

#Preview {
    PremiumScreen()
        .environment(PurchaseManager())
}

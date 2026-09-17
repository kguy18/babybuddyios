import SwiftUI

/// The "What's New in 1.1.0" sheet: a tinted glyph and a sentence per change, a primary Continue,
/// and a quieter invitation to tip.
///
/// A ``FittedSheet`` like ``StopTimerSheet`` and ``SupporterSheet``, so it is exactly as tall as
/// its rows — three changes don't leave half a screen of empty card below them, and a release with
/// five still scrolls rather than overflowing.
///
/// Holds no policy: ``WhatsNewStore`` decides whether it appears, and ``MainTabView`` owns what
/// happens after it closes. All this does is render ``WhatsNewRelease`` and report which button
/// was pressed.
struct WhatsNewSheet: View {
    let release: WhatsNewRelease
    /// Called with the button that was tapped. Not called for a swipe — the presenter infers that
    /// from a dismissal with no outcome, because SwiftUI's `onDismiss` cannot distinguish them.
    let onOutcome: (Analytics.WhatsNewAction) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Accessibility identifier on each row — see the row's own comment.
    static let rowIdentifier = "whatsNewRow"

    var body: some View {
        FittedSheet {
            VStack(spacing: 0) {
                header
                entries
                actions
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 30)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 6) {
            Text(release.title)
                .font(.system(size: 26, weight: .bold))
            versionChip
        }
        .padding(.bottom, 24)
        .accessibilityElement(children: .combine)
    }

    /// The brand-tinted pill carrying the release number — the same dot-and-label chip Settings
    /// uses for the server row, at pill scale.
    private var versionChip: some View {
        HStack(spacing: 6) {
            Circle().fill(BBColor.brand).frame(width: 6, height: 6)
            Text("Version \(release.version)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
        }
        .foregroundStyle(BBColor.brandAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(BBColor.brandTint, in: Capsule())
    }

    // MARK: Rows

    private var entries: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(release.entries) { entry in
                HStack(alignment: .top, spacing: 13) {
                    GlyphTile(symbol: entry.symbol, tint: entry.tint.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.subheadline.weight(.semibold))
                        Text(entry.blurb)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true) // wrap, don't truncate
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                // The rows are the one thing here that repeats, and their labels are editable copy
                // — so the UI test counts them by identifier rather than by text it would have to
                // be updated alongside `Docs/whats-new.md`.
                .accessibilityIdentifier(Self.rowIdentifier)
            }
        }
        .padding(.bottom, 22)
    }

    // MARK: Buttons

    private var actions: some View {
        VStack(spacing: 8) {
            Button("Continue") { finish(.continued) }
                .buttonStyle(.bbPrimary)
            // Deliberately the tinted style, not a second primary: tipping is optional and every
            // feature is free, so the ask sits below Continue and never competes with it.
            Button { finish(.support) } label: {
                Label("Support development", systemImage: "heart.fill")
            }
            .buttonStyle(.bbTinted)
            .accessibilityHint("Opens the supporter screen")
        }
    }

    private func finish(_ outcome: Analytics.WhatsNewAction) {
        onOutcome(outcome)
        dismiss()
    }
}

/// A soft tinted square holding an SF Symbol — ``ActivityTile``'s look for a glyph that isn't a
/// record kind. Same geometry (a 0.29 corner ratio, a 15%/22% tinted fill) so a What's New row and
/// a Timeline row read as the same component.
private struct GlyphTile: View {
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1
    let symbol: String
    let tint: Color

    var body: some View {
        let side = 38 * min(typeScale, 1.6)
        RoundedRectangle(cornerRadius: side * 0.29, style: .continuous)
            .fill(tint.opacity(scheme == .dark ? 0.22 : 0.15))
            .frame(width: side, height: side)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: 20 * min(typeScale, 1.6), weight: .semibold))
                    .foregroundStyle(tint)
            }
    }
}

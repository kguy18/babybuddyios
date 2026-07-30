import SwiftUI

/// The three support-nudge surfaces: the gentle ask (A), the milestone sheet (B), and the quiet
/// banner (D). Every one of them holds **no policy** — ``SupportNudgeManager`` decides whether they
/// appear and `DashboardView` presents them — and every blue button leads to the same
/// ``SupporterSheet``, so there is exactly one purchase flow in the app.

// MARK: - A · Gentle ask

/// The one-time centered card, over a scrim.
///
/// A card rather than a sheet on purpose: this is the app pausing once to say something, and a
/// sheet's drag indicator would invite a swipe that means neither yes nor no. Saying no is explicit
/// and cheap — "Maybe later", or a tap on the scrim.
struct SupportGentleAskCard: View {
    var onSupport: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            // Matches the quick-add stack's dim, the app's other full-screen scrim.
            Color.black.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)
                .transition(.opacity)

            // At accessibility text sizes the card is taller than the screen. `minHeight` keeps it
            // centered while it fits and lets it scroll once it doesn't — without this the body copy
            // is silently truncated mid-sentence, which is the one thing a card of copy can't afford.
            GeometryReader { proxy in
                ScrollView {
                    card
                        .padding(.horizontal, 28)
                        .padding(.vertical, 24)
                        .frame(minHeight: proxy.size.height, alignment: .center)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            SupporterHero()

            // Non-breaking spaces through the app's name: the title is two lines at default type on
            // a narrow card, and the break belongs after "Enjoying" rather than inside the name (the
            // mockup pins the same pair together for the same reason).
            Text("Enjoying Baby\u{00a0}Buddy\u{00a0}Companion?")
                .font(.system(size: 20, weight: .semibold))
                .padding(.top, 14)

            Text("Every feature is free — no locks, no subscriptions. If the app has earned a place in your routine, you can chip in to keep it growing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 7)

            Button("Become a Supporter", action: onSupport)
                .buttonStyle(.bbPrimary)
                .padding(.top, 20)

            QuietNudgeButton(title: "Maybe later", action: onDismiss)

            // The line that makes the whole thing fair: the ask is opt-out, and says so.
            Text("Reminders can be turned off in Settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 14)
        .background(BBColor.card, in: RoundedRectangle(cornerRadius: BBRadius.card, style: .continuous))
        .shadow(color: .black.opacity(0.30), radius: 24, y: 10)
        // Trap VoiceOver inside the card, so the dimmed Dashboard behind it isn't still swipeable.
        .accessibilityAddTraits(.isModal)
    }
}

// MARK: - B · Milestone

/// The celebratory bottom sheet for a crossed logging milestone.
///
/// Leads with what the customer did rather than what we want: the count is the headline, and the
/// planned thank-yous are named as planned — chips, not promises with dates on them.
struct SupportMilestoneSheet: View {
    /// The threshold being celebrated — one of ``SupportNudgeManager/milestones``.
    let count: Int
    var onSupport: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        FittedSheet {
            content
                .padding(.horizontal, 22)
                // Enough that the mascot's head clears the sheet's drag indicator.
                .padding(.top, 18)
                .padding(.bottom, 24)
                .overlay(alignment: .top) { Confetti() }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Same badge as the ask surfaces, keeping its own sparkles glyph — the milestone is the
            // most celebratory of the three, so a wave belongs here most of all.
            SupporterHero(systemImage: "sparkles")

            Text("Milestone")
                .font(.caption2.weight(.semibold))
                .kerning(0.6)
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            Text("\(count) activities logged")
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .padding(.top, 4)

            Text("Baby Buddy Companion has been there for every one of them. It's free for everyone — supporters are what keep it that way.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 7)

            perks

            Button("Become a Supporter", action: onSupport)
                .buttonStyle(.bbPrimary)
                .padding(.top, 20)

            QuietNudgeButton(title: "Not now", action: onDismiss)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    /// What supporting will eventually get you. Nothing here is gated today, and the header says
    /// "planned" precisely so it can't read as a promise that has already been broken.
    private var perks: some View {
        VStack(spacing: 0) {
            Text("Supporter thank-yous · planned")
                .font(.caption2.weight(.semibold))
                .kerning(0.5)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
                .padding(.top, 18)

            HStack(spacing: 8) {
                PerkChip(title: "Themes", color: BBColor.tummy)
                // `primary`, not `brand`: the latter is the one fixed token in the palette, and an
                // undimmed dot beside the adaptive one would be the only thing on the sheet ignoring
                // dark mode.
                PerkChip(title: "Alt app icons", color: BBColor.primary)
            }
            .padding(.top, 12)
        }
        .accessibilityElement(children: .combine)
    }
}

/// One planned thank-you: a neutral pill carrying a colored dot. Deliberately the same grammar as
/// the timeline's ``TagDotChip``, at the milestone sheet's slightly larger scale.
private struct PerkChip: View {
    let title: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(title).font(.footnote.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(BBColor.nested, in: Capsule())
    }
}

/// A scatter of small dots in the activity palette across the top of the milestone sheet — enough
/// to read as a celebration, static enough not to need a Reduce Motion opt-out.
private struct Confetti: View {
    private struct Dot {
        let alignment: Alignment
        let offset: CGSize
        let size: CGFloat
        let color: Color
    }

    private let dots: [Dot] = [
        Dot(alignment: .topLeading, offset: CGSize(width: 14, height: 16), size: 6, color: BBColor.primary),
        Dot(alignment: .topLeading, offset: CGSize(width: 48, height: 42), size: 5, color: BBColor.stop),
        Dot(alignment: .topLeading, offset: CGSize(width: 22, height: 74), size: 4, color: BBColor.pumping),
        Dot(alignment: .topTrailing, offset: CGSize(width: -22, height: 20), size: 6, color: BBColor.feeding),
        Dot(alignment: .topTrailing, offset: CGSize(width: -54, height: 50), size: 5, color: BBColor.tummy),
        Dot(alignment: .topTrailing, offset: CGSize(width: -18, height: 80), size: 4, color: BBColor.danger),
    ]

    var body: some View {
        ZStack {
            ForEach(dots.indices, id: \.self) { index in
                let dot = dots[index]
                Circle()
                    .fill(dot.color)
                    .frame(width: dot.size, height: dot.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: dot.alignment)
                    .offset(dot.offset)
            }
        }
        .frame(height: 100)
        .opacity(0.9)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - D · Quiet banner

/// The inline, dismissible Dashboard card — the de-escalation state, and the only surface left once
/// the popups have retired. Never blocks anything: it sits in the scroll content like any other card.
struct SupportBanner: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var onSupport: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: onSupport) { row }
                .buttonStyle(.plain)
                .accessibilityLabel("Free for everyone. If the app helps, you can support its development.")
                .accessibilityHint("Opens the supporter options")

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .padding(10) // a tappable target around a deliberately small glyph
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
    }

    @ViewBuilder private var row: some View {
        // At accessibility text sizes the pill can't share a line with the copy — it wraps inside its
        // own capsule and swells into a clipped blob — so the banner reflows into a column and the
        // call to action goes full width.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) { disc; copy }
                pill.frame(maxWidth: .infinity)
            }
            .modifier(BannerChrome())
        } else {
            HStack(spacing: 12) {
                disc
                copy
                Spacer(minLength: 4)
                pill
            }
            .modifier(BannerChrome())
        }
    }

    /// A card-colored disc, so the heart reads against the tinted banner rather than dissolving
    /// into it. Fixed at the mockup's 34pt (which pins it `flex:none`) — it's decorative, and the
    /// copy beside it is what needs the room at large type.
    private var disc: some View {
        Circle()
            .fill(BBColor.card)
            .frame(width: 34, height: 34)
            .overlay {
                Image(systemName: "heart.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(BBColor.brandAccent)
            }
    }

    private var copy: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Free for everyone")
                .font(.subheadline.weight(.semibold))
            Text("If the app helps, you can support its development.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true) // wrap, don't truncate
        }
    }

    private var pill: some View {
        Text("Support")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(BBColor.primary, in: Capsule())
    }
}

/// The banner's shared padding and tinted background, so its two layouts can't drift apart.
/// The extra top padding leaves the "×" a corner of its own, clear of the copy.
private struct BannerChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
            // Room for the "×" in the corner, so it never sits on top of the copy.
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BBColor.brandTint,
                        in: RoundedRectangle(cornerRadius: BBRadius.card, style: .continuous))
    }
}

// MARK: - Shared pieces

/// The quiet "no" under a nudge's blue button — full-width and easy to hit, but visually secondary.
/// Matches the supporter sheet's own dismiss button, so declining looks the same everywhere.
private struct QuietNudgeButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Previews

#Preview("Gentle ask") {
    ZStack {
        BBColor.surface.ignoresSafeArea()
        SupportGentleAskCard(onSupport: {}, onDismiss: {})
    }
}

#Preview("Milestone") {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SupportMilestoneSheet(count: 500, onSupport: {}, onDismiss: {})
        }
}

#Preview("Banner") {
    ZStack {
        BBColor.surface.ignoresSafeArea()
        SupportBanner(onSupport: {}, onDismiss: {}).padding()
    }
}

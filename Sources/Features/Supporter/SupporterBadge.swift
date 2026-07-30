import SwiftUI

/// The tinted glyph tile that fronts the supporter *sheets* — the same motif as ``ActivityTile``,
/// at the size the supporter surfaces use.
///
/// Baby Buddy deliberately does not peek over this one. His artwork ends in a flat cut where the
/// app icon's cloud used to be, so whatever he leans on has to be wide enough to hide that edge; a
/// 54pt tile leaves it showing on both sides and slices him in half. The gentle-ask popover has him
/// lean on the whole card instead, which is wide enough to do the job — see
/// ``SupportGentleAskCard``.
struct SupporterBadge: View {
    /// The glyph on the tile — a heart on the ask surfaces, sparkles on a milestone.
    var systemImage = "heart.fill"

    var body: some View {
        RoundedRectangle(cornerRadius: BBRadius.tile, style: .continuous)
            .fill(BBColor.brandTint)
            .frame(width: 54, height: 54)
            .overlay {
                Image(systemName: systemImage)
                    .font(.system(size: 25))
                    .foregroundStyle(BBColor.brandAccent)
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: 20) {
        SupporterBadge()
        SupporterBadge(systemImage: "sparkles")
    }
    .padding(40)
    .background(BBColor.card)
}

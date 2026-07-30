import SwiftUI

/// The badge that fronts a supporter surface: the tinted glyph tile, with Baby Buddy peeking over the
/// top of it and waving at whoever is about to chip in.
///
/// Layered rather than a single flat image so the tile keeps using the app's own tokens — the mascot
/// sits *behind* it in the `ZStack`, and the tile's opaque fill is what hides his cut-off bottom edge
/// and sells the peek. He is deliberately wider than the tile: the head clears its top and the raised
/// hand clears its right side, which is the whole gesture.
///
/// The artwork is lifted from the new alternate app icons, so the surface that asks for support is
/// fronted by the same character the icons introduce.
struct SupporterHero: View {
    /// The glyph on the tile — a heart on the ask surfaces.
    var systemImage = "heart.fill"

    /// The tile is the app's usual 54pt glyph tile (see ``NudgeHero``'s ancestor, ``ActivityTile``).
    private let tile: CGFloat = 54
    /// Wide enough that the head reads at a glance and the waving hand clears the tile's right edge.
    /// He straddles the tile — head past its left, hand past its right — which is what makes a 54pt
    /// badge look like something he is hiding behind.
    private let mascotWidth: CGFloat = 94
    /// Native 264×153, so the aspect is fixed here rather than left to the layout.
    private let mascotAspect: CGFloat = 153.0 / 264.0
    /// How far the mascot's flat bottom sits *inside* the tile. Enough that no seam can show, while
    /// still clearing his smile — too little reads as floating, too much buries the face.
    private let overlap: CGFloat = 13
    /// Nudges the head toward the tile's centre, since it sits left-of-centre in the artwork.
    private let mascotOffsetX: CGFloat = 2

    private var mascotHeight: CGFloat { mascotWidth * mascotAspect }

    var body: some View {
        ZStack(alignment: .bottom) {
            Image("mascot_peek_wave")
                .resizable()
                // The asset is ~3× its drawn size, so downscaling is what needs to look good.
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: mascotWidth, height: mascotHeight)
                .offset(x: mascotOffsetX, y: -(tile - overlap))

            RoundedRectangle(cornerRadius: BBRadius.tile, style: .continuous)
                .fill(BBColor.brandTint)
                .frame(width: tile, height: tile)
                .overlay {
                    Image(systemName: systemImage)
                        .font(.system(size: 25))
                        .foregroundStyle(BBColor.brandAccent)
                }
        }
        // Reserve the room the mascot needs above the tile, so he can't crowd the title beneath.
        .frame(width: mascotWidth, height: tile + mascotHeight - overlap, alignment: .bottom)
        // One decorative unit: the character is charm, not information.
        .accessibilityHidden(true)
    }
}

#Preview("Light") {
    SupporterHero().padding(40).background(BBColor.card)
}

#Preview("Dark") {
    SupporterHero().padding(40).background(BBColor.card).environment(\.colorScheme, .dark)
}

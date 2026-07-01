import SwiftUI

/// Maps each category to its custom Baby Buddy glyph asset (extracted from the web app's
/// Fontello icon font). These are template images, so they tint with the accent color.
extension EntityKind {
    /// Asset-catalog name of the custom glyph, e.g. `glyph_feeding`.
    var assetName: String { "glyph_\(rawValue)" }

    /// The category's icon as a tintable SwiftUI `Image`.
    var iconImage: Image { Image(assetName).renderingMode(.template) }

    /// Size-constrained icon view. Required because the custom glyphs have large intrinsic
    /// sizes and (unlike SF Symbols) don't scale to the surrounding font automatically.
    ///
    /// Marked decorative for VoiceOver: every place a glyph appears it sits beside a text label
    /// that already names the record kind, so an unlabeled "image" here would be redundant noise.
    func icon(_ size: CGFloat = 18) -> some View {
        iconImage.resizable().scaledToFit().frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

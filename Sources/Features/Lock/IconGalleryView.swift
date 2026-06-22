#if DEBUG
import SwiftUI

/// Debug-only gallery that renders every category's SF Symbol with its name, so the icon
/// choices can be reviewed exactly as the app draws them.
struct IconGalleryView: View {
    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(EntityKind.allCases) { kind in
                    VStack(spacing: 6) {
                        kind.iconImage
                            .resizable().scaledToFit()
                            .foregroundStyle(.tint)
                            .frame(width: 30, height: 30)
                        Text(kind.displayName).font(.footnote.weight(.medium))
                        Text(kind.assetName).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding()
        }
        .navigationTitle("Category Icons")
        .navigationBarTitleDisplayMode(.inline)
    }
}
#endif

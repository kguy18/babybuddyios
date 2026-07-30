import SwiftUI

/// Settings ▸ App Icon — a grid of the six shipped home-screen icons, tapping one to switch.
///
/// Every icon is free, so this screen has no locked state, no upsell, and no ``PurchaseManager``
/// dependency; see ``AppIconOption``.
struct AppIconPickerView: View {
    @Environment(AppIconManager.self) private var icons

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(AppIconOption.allCases) { option in
                        AppIconTile(option: option, isSelected: icons.selected == option) {
                            Task { await icons.select(option) }
                        }
                    }
                }

                if let error = icons.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(BBColor.danger)
                        .padding(.horizontal, 4)
                } else {
                    Text("Changing the icon shows a confirmation from iOS. It may take a moment to update on the Home Screen.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 28)
        }
        .background(BBColor.surface)
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// One icon in the grid: the artwork at the system's squircle rounding, its name, and a
/// brand-blue ring plus check badge when it's the one on the Home Screen.
private struct AppIconTile: View {
    let option: AppIconOption
    let isSelected: Bool
    var action: () -> Void

    /// iOS rounds app icons to ~22.4% of their width. Matching it here means the preview reads as
    /// the icon rather than as a picture of one.
    private static let cornerScale: CGFloat = 0.2237
    private static let side: CGFloat = 74

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                artwork
                Text(option.displayName)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? BBColor.brandAccent : .secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.15), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(option.displayName)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var artwork: some View {
        let shape = RoundedRectangle(cornerRadius: Self.side * Self.cornerScale, style: .continuous)
        return Group {
            if let image = UIImage(named: option.previewAssetName) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                // Only reachable if the catalog and `AppIconOption` fall out of step — draw a calm
                // placeholder rather than an empty hole, so the rest of the grid still works.
                BBColor.nested.overlay {
                    Image(systemName: "app.dashed")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: Self.side, height: Self.side)
        .clipShape(shape)
        .overlay {
            shape.strokeBorder(isSelected ? BBColor.brand : BBColor.fieldStroke,
                               lineWidth: isSelected ? 3 : 0.5)
        }
        .overlay(alignment: .bottomTrailing) {
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(5)
                    .background(BBColor.brand, in: Circle())
                    .overlay(Circle().stroke(BBColor.card, lineWidth: 2))
                    .offset(x: 5, y: 5)
            }
        }
    }
}

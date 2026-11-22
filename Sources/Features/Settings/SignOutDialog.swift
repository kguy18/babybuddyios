import SwiftUI

/// Confirms signing out: names the server being left, says what leaves this device, and — when the
/// queue isn't empty — that unsynced changes go with it.
///
/// A centred card rather than a `confirmationDialog`, which iOS 26 anchors to its source button as a
/// popover and strips of its cancel action, and rather than a plain `.alert`, which has no room for
/// the unsynced-changes warning as anything but another sentence of body copy. Presentation-only:
/// ``SettingsView`` owns the sign-out itself.
struct SignOutDialog: View {
    let host: String
    let pendingCount: Int
    let onCancel: () -> Void
    let onSignOut: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        SettingsDialogCard(label: String(localized: "Sign out of \(host)?"), onCancel: onCancel,
                           splitAtAccessibilitySizes: true) { split in
            VStack(alignment: .leading, spacing: split ? 2 : 14) {
                if split {
                    // Beside the fold at the largest sizes, the heading names the server: the
                    // copy then fits the pane without the server row.
                    Text("Sign out of \(host)?").font(.title3.weight(.semibold))
                } else {
                    HStack(spacing: 13) {
                        if !typeSize.isAccessibilitySize {
                            glyphTile(size: 46, radius: 14, symbol: "rectangle.portrait.and.arrow.right",
                                      font: .title3, tint: BBColor.danger, color: BBColor.danger)
                        }
                        Text("Sign out?").font(.title3.weight(.semibold))
                    }
                    serverRow
                    if pendingCount > 0 { pendingRow(showGlyph: true) }
                }
                Text("The activities cached on this device will be deleted. Nothing on your server changes — signing back in downloads them again.")
                    .font(split ? .subheadline : .body)
                    .foregroundStyle(.secondary)
            }
        } actions: {
            Button("Cancel", action: onCancel).buttonStyle(.bbNeutral)
            Button("Sign out", action: onSignOut)
                // The pale red in dark mode needs dark text for contrast.
                .buttonStyle(BBFilledButton(background: BBColor.danger,
                                            foreground: .adaptive(light: "FFFFFF", dark: "0C0E12")))
        } splitCopyAboveActions: {
            if pendingCount > 0 {
                DialogCopy(alignment: .leading) { pendingRow(showGlyph: false) }
            }
        }
    }

    /// The server being left, drawn as the row Settings already shows it in.
    private var serverRow: some View {
        HStack(spacing: 10) {
            if !typeSize.isAccessibilitySize {
                glyphTile(size: 26, radius: 8, symbol: "cloud", font: .footnote,
                          tint: BBColor.brand, color: BBColor.brandAccent)
            }
            Circle().fill(BBColor.success).frame(width: 7, height: 7)
            Text(host).font(.subheadline.weight(.medium))
                .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(BBColor.nested, in: RoundedRectangle(cornerRadius: BBRadius.control, style: .continuous))
    }

    /// Unsynced writes are the one thing sign-out destroys that the server can't give back, so they
    /// get the amber pending-changes vocabulary rather than a line of body copy.
    private func pendingRow(showGlyph: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            if showGlyph {
                glyphTile(size: 26, radius: 8, symbol: "icloud.and.arrow.up", font: .footnote,
                          tint: BBColor.warning, color: BBColor.warning, opacity: 0.35)
            }
            Text(pendingMessage)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(BBColor.warning.opacity(scheme == .dark ? 0.16 : 0.18),
                    in: RoundedRectangle(cornerRadius: BBRadius.control, style: .continuous))
    }

    private var pendingMessage: String {
        String(localized: "\(pendingCount) changes haven't reached this server yet. Signing out deletes them.")
    }

    /// The tinted glyph tile used across Settings, at the two sizes this dialog needs.
    private func glyphTile(size: CGFloat, radius: CGFloat, symbol: String, font: Font,
                           tint: Color, color: Color, opacity: Double? = nil) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(tint.opacity(opacity ?? (scheme == .dark ? 0.22 : 0.15)))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(font.weight(.semibold))
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .foregroundStyle(color)
                    .accessibilityHidden(true)
            }
    }
}

/// A modal card that keeps its actions visible while the copy scrolls.
struct SettingsDialogCard<Copy: View, Actions: View, ActionCopy: View>: View {
    let label: String
    let onCancel: () -> Void
    let splitAtAccessibilitySizes: Bool
    private let copy: (Bool) -> Copy
    private let actions: () -> Actions
    private let splitCopyAboveActions: () -> ActionCopy

    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var shown = false

    init(label: String, onCancel: @escaping () -> Void, splitAtAccessibilitySizes: Bool = false,
         @ViewBuilder copy: @escaping (Bool) -> Copy,
         @ViewBuilder actions: @escaping () -> Actions,
         @ViewBuilder splitCopyAboveActions: @escaping () -> ActionCopy = { EmptyView() }) {
        self.label = label
        self.onCancel = onCancel
        self.splitAtAccessibilitySizes = splitAtAccessibilitySizes
        self.copy = copy
        self.actions = actions
        self.splitCopyAboveActions = splitCopyAboveActions
    }

    var body: some View {
        ZStack {
            Color.black.opacity(scheme == .dark ? 0.55 : 0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)
                .accessibilityHidden(true)
            FoldSplitView {
                if splitCopy {
                    pane(maxWidth: .infinity) { DialogCopy(alignment: .leading) { copy(true) } }
                } else {
                    Color.clear.allowsHitTesting(false)
                }
            } main: { split in
                if split && splitCopy {
                    pane {
                        VStack(alignment: .leading, spacing: 12) {
                            splitCopyAboveActions()
                            actionGroup
                        }
                    }
                } else {
                    pane {
                        VStack(alignment: .leading, spacing: typeSize.isAccessibilitySize ? 12 : 16) {
                            DialogCopy(alignment: .leading) { copy(false) }
                            actionGroup
                        }
                    }
                }
            }
            .scaleEffect(shown ? 1 : 0.94)
            .opacity(shown ? 1 : 0)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityLabel(label)
        }
        .onAppear { withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { shown = true } }
    }

    private var splitCopy: Bool { splitAtAccessibilitySizes && typeSize.isAccessibilitySize }

    private func pane<Content: View>(maxWidth: CGFloat = 400,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        BBCard(padding: typeSize.isAccessibilitySize ? 14 : 20, content: content)
            .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 24, y: 12)
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, typeSize.isAccessibilitySize ? 10 : 16)
            // Split at the largest sizes, every point of height goes to the copy.
            .padding(.vertical, splitCopy ? 4 : typeSize.isAccessibilitySize ? 10 : 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var actionGroup: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout { actions() }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
    }
}

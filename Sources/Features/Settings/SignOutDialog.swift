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
    /// Drives the entrance. The cover it rides in is presented without its own transition (see
    /// `SettingsView.setSignOutDialog`), so the card animates itself in like an alert would.
    @State private var shown = false

    var body: some View {
        ZStack {
            Color.black.opacity(scheme == .dark ? 0.55 : 0.42)
                .ignoresSafeArea()
                .onTapGesture { onCancel() } // tapping out is the non-destructive way back
            card
                .padding(.horizontal, 30)
                .scaleEffect(shown ? 1 : 0.94)
                .opacity(shown ? 1 : 0)
        }
        .onAppear { withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) { shown = true } }
    }

    private var card: some View {
        BBCard(padding: 20) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 13) {
                    glyphTile(size: 46, radius: 14, symbol: "rectangle.portrait.and.arrow.right",
                              glyph: 21, tint: BBColor.danger, color: BBColor.danger)
                    Text("Sign out?").font(.system(size: 21, weight: .semibold))
                }
                serverRow
                if pendingCount > 0 { pendingRow }
                Text("The activities cached on this device will be deleted. Nothing on your server changes — signing back in downloads them again.")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Cancel") { onCancel() }
                        .buttonStyle(BBFilledButton(background: BBColor.controlFill, foreground: .primary))
                    Button("Sign out") { onSignOut() }
                        // Dark-on-tint: `danger` dims to a pale red in dark mode, where white fails.
                        .buttonStyle(BBFilledButton(background: BBColor.danger,
                                                    foreground: .adaptive(light: "FFFFFF", dark: "0C0E12")))
                }
                .padding(.top, 2)
            }
        }
        .shadow(color: .black.opacity(scheme == .dark ? 0.5 : 0.18), radius: 24, y: 12)
        .accessibilityAddTraits(.isModal)
        .accessibilityLabel("Sign out of \(host)?")
    }

    /// The server being left, drawn as the row Settings already shows it in.
    private var serverRow: some View {
        HStack(spacing: 10) {
            glyphTile(size: 26, radius: 8, symbol: "cloud", glyph: 13,
                      tint: BBColor.brand, color: BBColor.brandAccent)
            Circle().fill(BBColor.success).frame(width: 7, height: 7)
            Text(host).font(.system(size: 15, weight: .medium))
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(BBColor.nested, in: RoundedRectangle(cornerRadius: BBRadius.control, style: .continuous))
    }

    /// Unsynced writes are the one thing sign-out destroys that the server can't give back, so they
    /// get the amber pending-changes vocabulary rather than a line of body copy.
    private var pendingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            glyphTile(size: 26, radius: 8, symbol: "icloud.and.arrow.up", glyph: 13,
                      tint: BBColor.warning, color: BBColor.warning, opacity: 0.35)
            Text(pendingMessage)
                .font(.system(size: 14))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(BBColor.warning.opacity(scheme == .dark ? 0.16 : 0.18),
                    in: RoundedRectangle(cornerRadius: BBRadius.control, style: .continuous))
    }

    private var pendingMessage: String {
        let one = pendingCount == 1
        return "\(pendingCount) change\(one ? "" : "s") \(one ? "hasn't" : "haven't") reached this server yet. Signing out deletes \(one ? "it" : "them")."
    }

    /// The tinted glyph tile used across Settings, at the two sizes this dialog needs.
    private func glyphTile(size: CGFloat, radius: CGFloat, symbol: String, glyph: CGFloat,
                           tint: Color, color: Color, opacity: Double? = nil) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(tint.opacity(opacity ?? (scheme == .dark ? 0.22 : 0.15)))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: glyph, weight: .semibold))
                    .foregroundStyle(color)
            }
    }
}

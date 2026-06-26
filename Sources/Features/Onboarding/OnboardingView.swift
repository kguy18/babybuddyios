import SwiftUI
import UIKit

/// Server URL + API token entry, restyled to the Baby Buddy design system (light + dark).
/// Baby Buddy has no REST login endpoint, so the user scans a login QR — the fastest path,
/// presented as the solid brand-blue hero — or pastes a token from their web Settings page;
/// we validate it with a probe request. The connect/connecting/error states all live here.
struct OnboardingView: View {
    @Environment(AppSession.self) private var session

    @State private var serverURL = "https://demo.baby-buddy.net"
    @State private var token = ""
    @State private var isValidating = false
    @State private var showScanner = false
    @State private var showHelp = false
    @FocusState private var focusedField: Field?

    private enum Field { case url, token }

    private var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
            && !isValidating
    }

    /// An error is "live" only while we're not mid-validation (so the banner clears the instant
    /// the user retries). Drives the red banner, the red field border, and the "Try again" label.
    private var hasError: Bool { session.lastError != nil && !isValidating }

    /// Host shown in the "Reaching …" connecting subline, derived through the *same* normalization
    /// the sign-in uses — purely for display, the real upgrade still happens in `AppSession`.
    private var reachingHost: String {
        URL(string: AppSession.normalizedServerURLString(serverURL))?.host ?? serverURL
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                masthead
                qrHeroCard
                divider
                if hasError { errorBanner }
                manualCard
                supplemental
                primaryButton
                helpLink
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .padding(.bottom, 28)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(BBColor.surface.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .sheet(isPresented: $showScanner) {
            QRScannerSheet(onScan: handleScan)
        }
        .alert("Finding your details", isPresented: $showHelp) {
            Button("Got it", role: .cancel) {}
        } message: {
            Text("Scan: on your Baby Buddy site, open User → Add a Device to show a login QR code.\n\nManual: copy your API token from User → Settings, then paste it here. The server URL is your Baby Buddy web address.")
        }
        #if DEBUG
        .task {
            if ProcessInfo.processInfo.environment["BB_SCANNER_PREVIEW"] == "1" { showScanner = true }
        }
        #endif
    }

    // MARK: Masthead

    private var masthead: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: BBRadius.card, style: .continuous)
                .fill(BBColor.primary)
                .frame(width: 66, height: 66)
                .overlay {
                    EntityKind.child.iconImage
                        .resizable().scaledToFit()
                        .frame(width: 34, height: 34)
                        .foregroundStyle(.white)
                }
                .padding(.bottom, 14)
            Text("Baby Buddy")
                .font(.system(size: 26, weight: .semibold))
            Text("Connect to your self-hosted server")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 28)
    }

    // MARK: QR hero (solid primary — the fastest path)

    private var qrHeroCard: some View {
        Button {
            session.lastError = nil
            focusedField = nil
            showScanner = true
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(.white.opacity(0.18))
                    .frame(width: 46, height: 46)
                    .overlay {
                        Image(systemName: "qrcode")
                            .font(.system(size: 24, weight: .regular))
                            .foregroundStyle(.white)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Scan QR code")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Fastest way · from the server's app login")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BBColor.primary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isValidating)
        .opacity(isValidating ? 0.6 : 1)
        .padding(.bottom, 18)
    }

    // MARK: "or enter details" divider

    private var divider: some View {
        HStack(spacing: 12) {
            line
            Text("or enter details")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            line
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 16)
    }

    private var line: some View {
        Rectangle().fill(BBColor.fieldStroke).frame(height: 1)
    }

    // MARK: Manual entry (URL + token)

    private var manualCard: some View {
        BBCard(cornerRadius: BBRadius.tile, padding: 0) {
            VStack(spacing: 0) {
                fieldRow(label: "Server URL") {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(hasError ? Color.secondary : BBColor.success)
                    TextField("https://baby.mydomain.com", text: $serverURL)
                        .font(.system(size: 15))
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .url)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .token }
                }
                Rectangle().fill(BBColor.divider).frame(height: 1)
                fieldRow(label: "API token") {
                    Image(systemName: "key.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                    SecureField("Paste your API token", text: $token)
                        .font(.system(size: 15))
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .token)
                        .submitLabel(.go)
                        .onSubmit { if canSubmit { submit() } }
                    pasteButton
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: BBRadius.tile, style: .continuous)
                .strokeBorder(BBColor.danger, lineWidth: 1.5)
                .opacity(hasError ? 1 : 0)
        }
        .padding(.bottom, 8)
    }

    private func fieldRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) { content() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 15)
        .padding(.vertical, 12)
    }

    /// Paste is the primary gesture for the token field — a tinted pill that fills it in one tap.
    private var pasteButton: some View {
        Button {
            if let clip = UIPasteboard.general.string {
                token = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 13))
                Text("Paste")
                    .font(.system(size: 12.5, weight: .semibold))
            }
            .foregroundStyle(BBColor.brandAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(BBColor.brandTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: Supplemental row — caption / connecting subline (error uses the banner above)

    @ViewBuilder private var supplemental: some View {
        if isValidating {
            connectingRow
        } else if !hasError {
            httpsCaption
        }
    }

    private var httpsCaption: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 14))
                .foregroundStyle(BBColor.success)
            (Text("http://").monospaced()
                + Text(" is upgraded to ")
                + Text("https://").monospaced()
                + Text(" automatically"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.top, 8)
        .padding(.bottom, 22)
    }

    private var connectingRow: some View {
        HStack(spacing: 11) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(BBColor.brandTint)
                .frame(width: 38, height: 38)
                .overlay {
                    ProgressView().controlSize(.small).tint(BBColor.brandAccent)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text("Connecting…")
                    .font(.subheadline.weight(.semibold))
                Text("Reaching \(reachingHost)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    // MARK: Error banner (soft red — shown above the manual card)

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(BBColor.danger)
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't connect")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BBColor.danger)
                Text(session.lastError ?? "Check the URL, or that the server is online.")
                    .font(.caption)
                    .foregroundStyle(BBColor.danger.opacity(0.85))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BBColor.danger.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.bottom, 13)
    }

    // MARK: Primary action — Connect / Connecting / Try again

    @ViewBuilder private var primaryButton: some View {
        if isValidating {
            // Inert: connecting is in flight (see the live subline above).
            Label("Connecting…", systemImage: "")
                .labelStyle(.titleOnly)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .foregroundStyle(.secondary)
                .background(BBColor.controlFill, in: RoundedRectangle(cornerRadius: BBRadius.control, style: .continuous))
        } else if hasError {
            // Retry is not destructive, so it stays blue (tinted secondary), not red.
            Button(action: { submit() }) {
                Label("Try again", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bbTinted)
        } else {
            Button(action: { submit() }) {
                Label("Connect", systemImage: "powerplug.fill")
            }
            .buttonStyle(.bbTinted)
            .disabled(!canSubmit)
            .opacity(canSubmit ? 1 : 0.5)
        }
    }

    private var helpLink: some View {
        Button {
            focusedField = nil
            showHelp = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                Text("Where do I find these?")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(BBColor.brandAccent)
        }
        .buttonStyle(.plain)
        .padding(.top, 16)
    }

    // MARK: Logic (unchanged)

    /// Decode a scanned QR payload. On success, fill the fields and connect immediately;
    /// otherwise surface a hint so the user knows they scanned the wrong code.
    private func handleScan(_ raw: String) {
        guard let credentials = DeviceLoginQR.parse(raw) else {
            session.lastError = "That QR code isn't a Baby Buddy login code. Open User → Add a Device on your server to show it."
            return
        }
        serverURL = credentials.serverURL
        token = credentials.token
        submit(method: .qr)
    }

    private func submit(method: Analytics.SignInMethod = .manual) {
        focusedField = nil
        isValidating = true
        Task {
            let ok = await session.signIn(serverURL: serverURL, token: token)
            if ok { Analytics.onboardingCompleted(method: method) }
            isValidating = false
        }
    }
}

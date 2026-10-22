import SwiftUI

/// Signs a feedback-widget user in with an email code, or a password they already have
/// (kguydev/feedback-stack#18). Pushed in the feedback sheet from Sign In, and shown in place of Get
/// Help's chat while signed out. On success the session is in the web view's cookie store and
/// `onSignedIn` reloads the widget.
struct FeedbackSignInView: View {
    let widget: FeedbackWidget
    let onSignedIn: () -> Void
    /// No connection: the sheet shows its Mail fallback.
    let onUnreachable: () -> Void

    private enum Step { case email, code, password }
    private enum Field { case email, code, password }

    @State private var step = Step.email
    @State private var email = ""
    @State private var code = ""
    @State private var password = ""
    /// The code last sent to the server, so an unchanged wrong code isn't sent twice.
    @State private var triedCode: String?
    @State private var failure: FeedbackAuth.Failure?
    @State private var working = false
    @State private var resendAt = Date.distantPast
    /// The end of the server's rate-limit window, when it gives one.
    @State private var blockedUntil = Date.distantPast
    @FocusState private var focus: Field?
    @Environment(\.openURL) private var openURL

    /// Each send starts a 30-second wait before Resend.
    static let resendDelay: TimeInterval = 30

    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var emailLooksValid: Bool {
        let parts = trimmedEmail.split(separator: "@")
        return parts.count == 2 && parts[1].contains(".")
    }

    var body: some View {
        // Ticks each second for Resend's countdown and the end of a rate limit.
        SwiftUI.TimelineView(.periodic(from: .now, by: 1)) { timeline in
            ScrollView { content(now: timeline.date).padding(16) }
        }
        .background(BBColor.surface)
        .scrollDismissesKeyboard(.interactively)
    }

    private func content(now: Date) -> some View {
        let blocked = now < blockedUntil
        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Sign in")
                    .font(.title2.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Text(step == .code ? "Enter the 6-digit code we sent to \(trimmedEmail)." : context)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 4)
            switch step {
            case .email: emailStep(blocked: blocked)
            case .code: codeStep(now: now, blocked: blocked)
            case .password: passwordStep(blocked: blocked)
            }
        }
    }

    private var context: String {
        widget == .help ? "Sign in with your email so I can reply to you."
            : "Sign in with your email to post and vote."
    }

    // MARK: Steps

    private func emailStep(blocked: Bool) -> some View {
        VStack(spacing: 14) {
            emailField
            Button("Send Code", action: sendCode)
                .buttonStyle(.bbPrimary)
                .disabled(!emailLooksValid || working || blocked)
            quietLink("Use a password instead") { show(.password) }
        }
        .onAppear { if email.isEmpty { focus = .email } }
    }

    private func codeStep(now: Date, blocked: Bool) -> some View {
        VStack(spacing: 14) {
            field("Code", showsError: true) {
                TextField("6-digit code", text: $code)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .font(.system(size: 20, weight: .semibold).monospacedDigit())
                    .focused($focus, equals: .code)
                    .accessibilityLabel("Code")
                    .disabled(working || blocked)
                    .onChange(of: code) { _, typed in codeChanged(typed) }
            }
            if working { ProgressView().frame(maxWidth: .infinity) }
            let wait = Int(resendAt.timeIntervalSince(now).rounded(.up))
            quietLink(wait > 0 ? "Resend code in \(wait)s" : "Resend code", action: sendCode)
                .disabled(wait > 0 || working || blocked)
            quietLink("Use a different email") { show(.email) }
        }
        .onAppear { focus = .code }
    }

    private func passwordStep(blocked: Bool) -> some View {
        VStack(spacing: 14) {
            emailField
            field("Password", showsError: true) {
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit(signInWithPassword)
            }
            Button("Sign In", action: signInWithPassword)
                .buttonStyle(.bbPrimary)
                .disabled(!emailLooksValid || password.isEmpty || working || blocked)
            quietLink("Use an email code instead") { show(.email) }
            // Rare enough that the portal's own reset flow, in Safari, is enough.
            quietLink("Forgot password?") { openURL(FeedbackWidget.serverURL.appending(path: "auth/login")) }
        }
    }

    /// The email field; send errors show under it on the email step.
    private var emailField: some View {
        field("Email", showsError: step == .email) {
            TextField("you@example.com", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(step == .email ? .send : .next)
                .focused($focus, equals: .email)
                .accessibilityLabel("Email")
                .onSubmit { step == .email ? sendCode() : (focus = .password) }
        }
    }

    // MARK: Pieces

    /// A labelled field on a card, outlined and with the error under it when it has one.
    private func field<Content: View>(_ label: String, showsError: Bool,
                                      @ViewBuilder content: () -> Content) -> some View {
        let message = showsError ? failure?.message : nil
        let input = content()
        return VStack(alignment: .leading, spacing: 6) {
            BBCard(cornerRadius: BBRadius.tile, padding: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    input.font(.system(size: 15))
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: BBRadius.tile, style: .continuous)
                    .strokeBorder(BBColor.danger, lineWidth: 1.5)
                    .opacity(message == nil ? 0 : 1)
            }
            if let message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(BBColor.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    private func quietLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline)
            .foregroundStyle(BBColor.brandAccent)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
            .buttonStyle(.plain)
    }

    // MARK: Actions

    private func show(_ next: Step) {
        failure = nil
        code = ""
        triedCode = nil
        step = next
    }

    /// Digits only, at most six; the sixth submits.
    private func codeChanged(_ typed: String) {
        let digits = String(typed.filter(\.isNumber).prefix(6))
        guard digits == typed else { code = digits; return }
        guard digits.count == 6, digits != triedCode, !working, Date.now >= blockedUntil else { return }
        triedCode = digits
        run(.verifyCode(email: trimmedEmail, code: digits))
    }

    private func sendCode() {
        guard emailLooksValid, !working, Date.now >= blockedUntil else { return }
        run(.sendCode(email: trimmedEmail)) {
            step = .code
            code = ""
            triedCode = nil
            resendAt = .now.addingTimeInterval(Self.resendDelay)
        }
    }

    private func signInWithPassword() {
        guard emailLooksValid, !password.isEmpty, !working, Date.now >= blockedUntil else { return }
        run(.password(email: trimmedEmail, password: password))
    }

    private func run(_ request: FeedbackAuth.Request, onSent: @escaping () -> Void = {}) {
        working = true
        failure = nil
        Task {
            let outcome = await FeedbackSession.perform(request)
            switch outcome {
            case .sent:
                working = false
                onSent()
            case .signedIn(let session):
                await FeedbackSession.save(session)
                working = false
                onSignedIn()
            case .failed(.unreachable):
                working = false
                onUnreachable()
            case .failed(let failure):
                working = false
                self.failure = failure
                if case .rateLimited(let wait?) = failure { blockedUntil = .now.addingTimeInterval(wait) }
            }
        }
    }
}

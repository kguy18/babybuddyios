import SwiftUI

/// Settings ▸ Feedback ▸ Send Feedback: a note from me, the ways into the feedback widget
/// (``FeedbackSheet``), the roadmap, and while signed in the feedback account.
///
/// When the feedback server can't be reached, the sheet's Email Support falls back to Mail: offer
/// to attach diagnostics, then present the composer (or a `mailto:` link without a Mail account).
struct SendFeedbackView: View {
    @State private var feedback: FeedbackWidget?
    /// Set by the sheet's Email Support; the Mail flow starts once the sheet is gone.
    @State private var emailAfterFeedback = false
    @State private var showingSupporter = false
    @State private var showingContactOptions = false
    @State private var mailPayload: MailPayload?
    @State private var showingMailUnavailable = false
    /// Who is signed in to feedback, for the Feedback Account row; `nil` until the web view's
    /// cookie store answers.
    @State private var account: FeedbackSession.Account?
    @State private var showingAccount = false
    @Environment(\.openURL) private var openURL

    /// The note's "supporters like you" link: the app's own supporter link, caught by the note's
    /// `openURL` handler so the sheet opens over this screen.
    private static let supporterLink = URL(string: "babybuddy://supporter")!

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                note
                actionsCard
                moreCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(BBColor.surface)
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAccount() }
        .navigationDestination(isPresented: $showingAccount) {
            if case .signedIn(let email) = account {
                FeedbackAccountView(email: email) { account = .signedOut }
            }
        }
        .sheet(item: $feedback, onDismiss: {
            Task { await refreshAccount() }
            if emailAfterFeedback {
                emailAfterFeedback = false
                showingContactOptions = true
            }
        }) { widget in
            FeedbackSheet(widget: widget) { emailAfterFeedback = true }
        }
        .sheet(isPresented: $showingSupporter) { SupporterSheet(source: .settings) }
        // `.alert`, not `confirmationDialog`, which iOS 26 shows as a popover without its Cancel.
        .alert("Contact Support", isPresented: $showingContactOptions) {
            Button("Include Device Details") { presentMail(includeDiagnostics: true) }
            Button("Don't Include") { presentMail(includeDiagnostics: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Attach your device model, iOS version, and app version to help us investigate? Nothing else is shared.")
        }
        .sheet(item: $mailPayload) { payload in
            MailComposeView(recipient: SupportContact.recipient,
                            subject: SupportContact.subject,
                            body: payload.body) { _ in mailPayload = nil }
                .ignoresSafeArea()
        }
        .alert("Set Up Mail", isPresented: $showingMailUnavailable) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("No email account is set up on this device. You can reach us at \(SupportContact.recipient).")
        }
    }

    // MARK: Note

    /// Markdown links: VoiceOver reads each as a link, and the supporter one opens the sheet here.
    private var note: some View {
        BBCard(cornerRadius: BBRadius.card, padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Hi, I'm [Kurtis](https://github.com/kguy18). I build Baby Buddy Companion in my free time, and it's [open source on GitHub](https://github.com/kguy18/babybuddyios). It's free, and [supporters like you](babybuddy://supporter) keep it going.")
                Text("I do read everything and try to reply to everyone.")
                Text("To post, vote or chat, you'll sign in with your email. No password needed.")
                Text("This app is an independent client not affiliated with Baby Buddy the open source server project, so if you have server-side issues please open a ticket on [their GitHub](https://github.com/babybuddy/babybuddy).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .lineSpacing(3)
            .tint(BBColor.brandAccent)
            .fixedSize(horizontal: false, vertical: true)
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url == Self.supporterLink else { return .systemAction }
            showingSupporter = true
            return .handled
        })
    }

    // MARK: Rows

    private var actionsCard: some View {
        BBCard(cornerRadius: BBRadius.card, padding: 0) {
            VStack(spacing: 0) {
                actionRow(.board, symbol: "lightbulb", tint: BBColor.brand,
                          subtitle: "Suggest an idea or vote on others")
                Rectangle().fill(BBColor.divider).frame(height: 0.5)
                actionRow(.help, symbol: "bubble.left", tint: BBColor.info,
                          subtitle: "Report a problem or ask a question")
            }
            .padding(.horizontal, 15)
        }
    }

    /// The roadmap, and while signed in the way to the feedback account.
    private var moreCard: some View {
        BBCard(cornerRadius: BBRadius.card, padding: 0) {
            VStack(spacing: 0) {
                actionRow(.roadmap, symbol: "map", tint: BBColor.note, subtitle: nil)
                if case .signedIn(let email) = account {
                    Rectangle().fill(BBColor.divider).frame(height: 0.5)
                    Button { showingAccount = true } label: {
                        SettingsRow(symbol: "person", tint: BBColor.note, title: "Feedback Account",
                                    subtitle: email) { chevron }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 15)
        }
    }

    private func actionRow(_ widget: FeedbackWidget, symbol: String, tint: Color, subtitle: String?) -> some View {
        Button { feedback = widget } label: {
            SettingsRow(symbol: symbol, tint: tint, title: widget.title, subtitle: subtitle) { chevron }
        }
        .buttonStyle(.plain)
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    private func refreshAccount() async {
        account = await FeedbackSession.account()
    }

    // MARK: Mail fallback

    /// Present the mail composer seeded with (optionally) diagnostics. Falls back to a `mailto:`
    /// link, then a "set up Mail" alert, when the in-app composer can't be shown.
    private func presentMail(includeDiagnostics: Bool) {
        if SupportContact.canSendMail {
            mailPayload = MailPayload(body: SupportContact.body(includeDiagnostics: includeDiagnostics))
        } else if let url = SupportContact.mailtoURL(includeDiagnostics: includeDiagnostics) {
            openURL(url) { accepted in
                if !accepted { showingMailUnavailable = true }
            }
        } else {
            showingMailUnavailable = true
        }
    }
}

/// Wraps a seeded email body so `.sheet(item:)` has an `Identifiable` to present.
private struct MailPayload: Identifiable {
    let id = UUID()
    let body: String
}

/// Send Feedback ▸ Feedback Account: who is signed in, Sign Out, and Delete Feedback Account.
/// Signing out, or sending the deletion request, goes back to Send Feedback.
struct FeedbackAccountView: View {
    /// `nil` when the server couldn't be asked.
    let email: String?
    let onSignedOut: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmingSignOut = false
    @State private var confirmingDeletion = false
    /// Delete Feedback Account's request, in the Mail composer.
    @State private var deletionMail: MailPayload?
    /// Mail sent the request; the screen closes once the composer has.
    @State private var deletionSent = false
    /// The request couldn't go out; the line in its place says where to write instead.
    @State private var deletionFailed = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                card
                Text("Your Baby Buddy data isn't affected. This account is only for posting, voting and chatting with me.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(BBColor.surface)
        .safeAreaInset(edge: .bottom) {
            deletion
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
                .background(BBColor.surface)
        }
        .navigationTitle("Feedback Account")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign out of feedback?", isPresented: $confirmingSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    await FeedbackSession.signOut()
                    onSignedOut()
                    dismiss()
                }
            }
        } message: {
            Text("You'll need your email to post, vote or chat again. Your Baby Buddy data isn't affected.")
        }
        .alert("Delete your feedback account?", isPresented: $confirmingDeletion) {
            Button("Cancel", role: .cancel) {}
            Button("Request Deletion", role: .destructive) { requestDeletion() }
        } message: {
            Text("I'll remove your feedback account within 7 days. Your posts and comments stay on the board under \"Deleted user\", your votes are removed, and your support chats are kept without your email. Your Baby Buddy data isn't affected.")
        }
        .sheet(item: $deletionMail, onDismiss: {
            if deletionSent { dismiss() }
        }) { payload in
            MailComposeView(recipient: SupportContact.recipient,
                            subject: SupportContact.deletionSubject,
                            body: payload.body) { result in
                deletionMail = nil
                switch result {
                case .sent: deletionSent = true
                case .failed: deletionFailed = true
                default: break // Cancelled or saved as a draft: nothing was requested.
                }
            }
            .ignoresSafeArea()
        }
    }

    private var card: some View {
        BBCard(cornerRadius: BBRadius.card, padding: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Text(email?.first.map { String($0).uppercased() } ?? "")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BBColor.brandAccent)
                        .frame(width: 34, height: 34)
                        .background(BBColor.brandTint, in: Circle())
                        .overlay {
                            if email == nil {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(BBColor.brandAccent)
                            }
                        }
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 1) {
                        if let email {
                            Text("Signed in to feedback as")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text(email)
                                .font(.system(size: 16))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        } else {
                            Text("Signed in to feedback")
                                .font(.system(size: 16))
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 12)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(email.map { "Signed in to feedback as \($0)" } ?? "Signed in to feedback")
                Rectangle().fill(BBColor.divider).frame(height: 0.5)
                Button { confirmingSignOut = true } label: {
                    Text("Sign Out of Feedback")
                        .font(.system(size: 16))
                        .foregroundStyle(BBColor.danger)
                        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 15)
        }
    }

    /// Delete Feedback Account, or after a failed request, where to write and Try Again.
    @ViewBuilder private var deletion: some View {
        if deletionFailed {
            VStack(spacing: 0) {
                Text("Couldn't send your request. Try again, or email \(SupportContact.recipient).")
                    .font(.subheadline)
                    .foregroundStyle(BBColor.danger)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                Button("Try Again") { requestDeletion() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BBColor.brandAccent)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
        } else {
            Button("Delete Feedback Account") { confirmingDeletion = true }
                .font(.subheadline)
                .foregroundStyle(BBColor.danger)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
                .buttonStyle(.plain)
        }
    }

    /// Opens the request in Mail. Without a Mail account there's no way to send it from here,
    /// so the line says where to write instead.
    private func requestDeletion() {
        if Self.stubsSentMail {
            dismiss()
        } else if SupportContact.canSendMail {
            deletionMail = MailPayload(body: SupportContact.deletionBody(feedbackEmail: email))
        } else {
            deletionFailed = true
        }
    }

    /// `BB_FEEDBACK_DELETION_MAIL=sent`, honored only with `BB_UITEST`: the request counts as
    /// sent without the composer, which the simulator can't show without a Mail account.
    private static let stubsSentMail = ProcessInfo.processInfo.environment["BB_UITEST"] == "1"
        && ProcessInfo.processInfo.environment["BB_FEEDBACK_DELETION_MAIL"] == "sent"
}

import SwiftUI
import UIKit

/// Settings ▸ Feedback ▸ Send Feedback: a note from me, the ways into the feedback widget
/// (``FeedbackSheet``), app details to paste into a message, and the roadmap.
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
    /// Who is signed in to feedback, for the signed-in card; `nil` until the web view's cookie
    /// store answers.
    @State private var account: FeedbackSession.Account?
    @State private var confirmingSignOut = false
    /// Set by Sign Out, for the line that replaces the card.
    @State private var signedOut = false
    @State private var confirmingDeletion = false
    /// Delete Feedback Account's request, in the Mail composer.
    @State private var deletionMail: MailPayload?
    @State private var deletion: DeletionRequest?

    /// How the last deletion request went, for the line under the card's rows.
    private enum DeletionRequest { case sent, failed }
    @Environment(\.openURL) private var openURL

    /// Wraps the seeded email body so `.sheet(item:)` has an `Identifiable` to present.
    private struct MailPayload: Identifiable {
        let id = UUID()
        let body: String
    }

    /// The note's "supporters like you" link: the app's own supporter link, caught by the note's
    /// `openURL` handler so the sheet opens over this screen.
    private static let supporterLink = URL(string: "babybuddy://supporter")!

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                note
                actionsCard
                feedbackAccount
                copyDetails
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .background(BBColor.surface)
        .safeAreaInset(edge: .bottom) {
            Button { feedback = .roadmap } label: {
                HStack(spacing: 4) {
                    Text("See roadmap and updates")
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .font(.subheadline)
                .foregroundStyle(BBColor.brandAccent)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .background(BBColor.surface)
        }
        .overlay(alignment: .bottom) { UndoToastView().padding(.bottom, 60) }
        .navigationTitle("Send Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .task { await refreshAccount() }
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
        .alert("Sign out of feedback?", isPresented: $confirmingSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    await FeedbackSession.signOut()
                    account = .signedOut
                    signedOut = true
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
        .sheet(item: $deletionMail) { payload in
            MailComposeView(recipient: SupportContact.recipient,
                            subject: SupportContact.deletionSubject,
                            body: payload.body) { result in
                deletionMail = nil
                switch result {
                case .sent: deletion = .sent
                case .failed: deletion = .failed
                default: break // Cancelled or saved as a draft: nothing was requested.
                }
            }
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

    // MARK: Actions

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

    private func actionRow(_ widget: FeedbackWidget, symbol: String, tint: Color, subtitle: String) -> some View {
        Button { feedback = widget } label: {
            SettingsRow(symbol: symbol, tint: tint, title: widget.title, subtitle: subtitle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Feedback account

    private func refreshAccount() async {
        account = await FeedbackSession.account()
        if account != .signedOut { signedOut = false }
    }

    /// While signed in, whose feedback account this is and a way out of it; after signing out, a
    /// line saying so. Nothing while signed out otherwise.
    @ViewBuilder private var feedbackAccount: some View {
        if case .signedIn(let email) = account {
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
                    dangerRow("Sign Out of Feedback") { confirmingSignOut = true }
                    Rectangle().fill(BBColor.divider).frame(height: 0.5)
                    dangerRow("Delete Feedback Account") { confirmingDeletion = true }
                    deletionStatus
                }
                .padding(.horizontal, 15)
            }
        } else if signedOut {
            Text("Signed out. You'll sign in again next time you post, vote or chat.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
        }
    }

    private func dangerRow(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(BBColor.danger)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var deletionStatus: some View {
        switch deletion {
        case .sent:
            Text("Deletion requested. I'll remove your account within 7 days.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
        case .failed:
            VStack(alignment: .leading, spacing: 2) {
                Text("Couldn't send your request. Try again, or email \(SupportContact.recipient).")
                    .font(.footnote)
                    .foregroundStyle(BBColor.danger)
                Button("Try Again") { requestDeletion() }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BBColor.brandAccent)
                    .frame(minHeight: 44)
                    .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case nil:
            EmptyView()
        }
    }

    /// Opens the request in Mail. Without a Mail account there's no way to send it from here,
    /// so the line says where to write instead.
    private func requestDeletion() {
        guard case .signedIn(let email) = account else { return }
        if Self.stubsSentMail {
            deletion = .sent
        } else if SupportContact.canSendMail {
            deletionMail = MailPayload(body: SupportContact.deletionBody(feedbackEmail: email))
        } else {
            deletion = .failed
        }
    }

    /// `BB_FEEDBACK_DELETION_MAIL=sent`, honored only with `BB_UITEST`: the request counts as
    /// sent without the composer, which the simulator can't show without a Mail account.
    private static let stubsSentMail = ProcessInfo.processInfo.environment["BB_UITEST"] == "1"
        && ProcessInfo.processInfo.environment["BB_FEEDBACK_DELETION_MAIL"] == "sent"

    // MARK: Copy app details

    private var copyDetails: some View {
        VStack(spacing: 2) {
            Button {
                UIPasteboard.general.string = SupportContact.diagnostics
                UndoToastCenter.shared.confirm("App details copied")
            } label: {
                Label("Copy app details", systemImage: "doc.on.doc")
                    .font(.subheadline)
                    .foregroundStyle(BBColor.brandAccent)
                    .frame(minHeight: 44)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Text("Paste them into your message so I can see your version and device.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
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

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
        .sheet(item: $feedback, onDismiss: {
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
                            body: payload.body) { mailPayload = nil }
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

import SwiftUI

/// The "What's New" card shown once on the first launch after an update, and on demand from
/// Settings ▸ Contact Support ▸ What's New.
///
/// Presentation note: this rides in a `.fullScreenCover`, not a `.sheet`. A sheet leaves the iOS 26
/// floating tab bar visible underneath, which reads as the app still being interactive behind a
/// screen that is asking to be dismissed — the same reason ``SignOutDialog`` uses a cover.
struct WhatsNewView: View {
    let note: ReleaseNote
    /// Carried onto every signal from here, so the automatic card and a deliberate visit from
    /// Settings can be told apart.
    let source: Analytics.WhatsNewSource
    /// "Continue" on first launch; Settings passes "Done", where nothing is being continued.
    var dismissTitle = String(localized: "Continue")
    /// Called after the cover is dismissed, so the caller can record the version it showed.
    var onDismiss: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var showingSupporter = false
    /// Set by the dismiss button, so leaving any other way reports as a dismissal rather than a
    /// read. Presenting the tip sheet over this view doesn't disturb it.
    @State private var continued = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    masthead
                    card.padding(.horizontal, 16).padding(.top, 24)
                }
                .padding(.bottom, 16)
            }
            footer
        }
        .background(BBColor.surface)
        .onAppear { Analytics.whatsNewShown(source: source) }
        // `showingSupporter` is part of the guard, not just `continued`: SwiftUI is inconsistent
        // about whether a presenting view gets `onDisappear` when a sheet covers it, and counting
        // "opened the tip sheet" as a dismissal — then counting the real one later too — would
        // double-report. Suppressed while the tip sheet is up, it reports once either way.
        .onDisappear {
            guard !continued, !showingSupporter else { return }
            Analytics.whatsNewDismissed(source: source)
        }
        .sheet(isPresented: $showingSupporter) {
            // Its own source, so a tip from here is never counted as a Settings tip. Deliberately
            // one source whether the card was opened on launch or from Settings — this answers
            // which surface earned the tip, and `WhatsNew.supporterTapped` splits the two on the
            // card's own side if that is ever the question.
            SupporterSheet(source: .whatsNew)
        }
    }

    // MARK: Pieces

    private var masthead: some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .fill(BBColor.brandTint)
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(BBColor.brandAccent)
                }
            Text("What's New")
                .font(.system(size: 28, weight: .semibold))
                .padding(.top, 15)
            Text("Version \(note.version)")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(BBColor.brandAccent)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(BBColor.brandTint, in: Capsule())
                .padding(.top, 7)
        }
        .padding(.top, 26)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var card: some View {
        BBCard(cornerRadius: BBRadius.card, padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(note.new.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { divider }
                    row(item)
                }
                if !note.fixed.isEmpty {
                    fixedHeader
                    ForEach(note.fixed, id: \.self) { fixedRow($0) }
                        .padding(.bottom, 6)
                }
            }
        }
    }

    private func row(_ item: ReleaseNote.Item) -> some View {
        HStack(alignment: .top, spacing: 13) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item.icon.tint.opacity(0.15))
                .frame(width: 34, height: 34)
                .overlay {
                    Image(systemName: item.icon.symbol)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(item.icon.tint)
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString(item.title, comment: "Bundled release note title")).font(.system(size: 15.5, weight: .semibold))
                if !item.body.isEmpty {
                    Text(NSLocalizedString(item.body, comment: "Bundled release note body"))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
        .accessibilityElement(children: .combine)
    }

    private var fixedHeader: some View {
        VStack(spacing: 0) {
            divider
            SectionHeader(String(localized: "Also fixed"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 6)
        }
    }

    private func fixedRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BBColor.success)
                .padding(.top, 1)
            Text(NSLocalizedString(text, comment: "Bundled release note fix"))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button(dismissTitle) {
                continued = true
                Analytics.whatsNewContinued(source: source)
                onDismiss()
                dismiss()
            }
            .buttonStyle(.bbPrimary)

            Button {
                Analytics.whatsNewSupporterTapped(source: source)
                // Opening the supporter sheet from here takes the nudge policy's slot; the card
                // on its own does not.
                SupportNudgeStore.shared.snoozeNudges()
                showingSupporter = true
            } label: {
                Label("Support development", systemImage: "heart.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BBColor.brandAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 30)
        .background(BBColor.surface)
    }

    private var divider: some View {
        Rectangle().fill(BBColor.divider).frame(height: 0.5)
    }
}

#Preview {
    WhatsNewView(note: ReleaseNote(
        version: "1.0.3",
        new: [
            .init(icon: .sync, title: String(localized: "Sync problems are visible"),
                  body: String(localized: "Rejected records stop retrying and wait in Pending Changes with the reason.")),
            .init(icon: .alert, title: String(localized: "Flagged on the Timeline"),
                  body: String(localized: "Records that failed to sync show a red warning. Tap it to see why.")),
        ],
        fixed: [String(localized: "Repeating a feeding keeps the right end time")]),
        source: .launch)
}

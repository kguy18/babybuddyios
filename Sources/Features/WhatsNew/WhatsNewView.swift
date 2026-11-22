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

    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var wide = false

    var body: some View {
        // iPhone Duo's open display: the heading and buttons left of the fold, the list right of
        // it. The launch card is a full-screen cover, which FoldSplitView splits at the fold. From
        // Settings it is a narrower sheet centred on the fold, so it uses the sheet columns.
        FoldSplitView {
            sidePane
        } main: { split in
            if split {
                list
            } else if wide {
                SheetColumns(wide: wide) {
                    sidePane
                } trailing: {
                    list
                }
            } else {
                VStack(spacing: 0) {
                    // At accessibility sizes the support link scrolls with the list, so the
                    // footer keeps to the one button and leaves the list room.
                    list(withMasthead: true, withSupport: typeSize.isAccessibilitySize)
                    footer(withSupport: !typeSize.isAccessibilitySize)
                }
            }
        }
        .trackingWide($wide)
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

    private var releaseInset: CGFloat { typeSize.isAccessibilitySize ? 8 : 16 }

    private var sidePane: some View {
        VStack(spacing: 0) {
            if typeSize.isAccessibilitySize {
                ScrollView {
                    masthead
                    supportButton.padding(.horizontal, 20).padding(.top, 8)
                }
                footer(withSupport: false)
            } else {
                Spacer(minLength: 0)
                masthead
                Spacer(minLength: 0)
                footer()
            }
        }
    }

    private var list: some View { list(withMasthead: false, withSupport: false) }

    /// The release items, scrolling. The indicator flashes as it opens, so a list that runs past
    /// the buttons at large text sizes shows that it scrolls.
    private func list(withMasthead: Bool, withSupport: Bool) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                if withMasthead { masthead }
                card
                    .padding(.horizontal, releaseInset)
                    .padding(.top, typeSize.isAccessibilitySize ? 8 : 24)
                if withSupport { supportButton.padding(.horizontal, 20).padding(.top, 8) }
            }
            .padding(.bottom, 16)
        }
        .scrollIndicatorsFlash(onAppear: true)
        .accessibilityIdentifier("whats-new-releases")
    }

    private var masthead: some View {
        VStack(spacing: 0) {
            if !typeSize.isAccessibilitySize {
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(BBColor.brandTint)
                    .frame(width: 56, height: 56)
                    .overlay {
                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(BBColor.brandAccent)
                    }
                    .accessibilityHidden(true)
            }
            Text("What's New")
                .font((typeSize.isAccessibilitySize ? Font.headline : .title).weight(.semibold))
                .padding(.top, typeSize.isAccessibilitySize ? 0 : 15)
                .accessibilityAddTraits(.isHeader)
            Text("Version \(note.version)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BBColor.brandAccent)
                .padding(.horizontal, 11)
                .padding(.vertical, 5)
                .background(BBColor.brandTint, in: Capsule())
                .padding(.top, typeSize.isAccessibilitySize ? 3 : 7)
        }
        .padding(.top, typeSize.isAccessibilitySize ? 8 : 26)
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
            if !typeSize.isAccessibilitySize {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(item.icon.tint.opacity(0.15))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: item.icon.symbol)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(item.icon.tint)
                    }
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(NSLocalizedString(item.title, comment: "Bundled release note title"))
                    .font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                if !item.body.isEmpty {
                    Text(NSLocalizedString(item.body, comment: "Bundled release note body"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, releaseInset)
        .padding(.vertical, typeSize.isAccessibilitySize ? 8 : 15)
        .accessibilityElement(children: .combine)
    }

    private var fixedHeader: some View {
        VStack(spacing: 0) {
            divider
            SectionHeader(String(localized: "Also fixed"))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, releaseInset)
                .padding(.top, 14)
                .padding(.bottom, 6)
        }
    }

    private func fixedRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BBColor.success)
                .padding(.top, 1)
            Text(NSLocalizedString(text, comment: "Bundled release note fix"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, releaseInset)
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func footer(withSupport: Bool = true) -> some View {
        VStack(spacing: 8) {
            Button(dismissTitle) {
                continued = true
                Analytics.whatsNewContinued(source: source)
                onDismiss()
                dismiss()
            }
            .buttonStyle(.bbPrimary)

            if withSupport { supportButton }
        }
        .padding(.horizontal, 20)
        .padding(.top, typeSize.isAccessibilitySize ? 6 : 10)
        .padding(.bottom, typeSize.isAccessibilitySize ? 8 : 30)
        .background(BBColor.surface)
    }

    private var supportButton: some View {
        Button {
            Analytics.whatsNewSupporterTapped(source: source)
            // Opening the supporter sheet from here takes the nudge policy's slot; the card
            // on its own does not.
            SupportNudgeStore.shared.snoozeNudges()
            showingSupporter = true
        } label: {
            Label("Support development", systemImage: "heart.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BBColor.brandAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Past this size "development" is wider than the phone.
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
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

import SwiftUI
import SwiftData

/// The offline-first sync queue, laid bare: every write waiting to reach the server, oldest
/// first — queued record changes and queued photo uploads alike. Each row says what is waiting
/// and shows the record's detail.
///
/// Rows come in two states. **Waiting** work just hasn't been delivered yet (offline, or the
/// server is down) and needs nothing from the user. **Blocked** work was rejected by the server
/// in a way that re-sending can't fix, so sync stopped retrying it and parked it here: those rows
/// carry the server's reason and an explicit Retry. Either way Discard cancels the queued work —
/// it edits the *queue*, never the underlying record, which it never opens for editing.
struct PendingChangesView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PendingMutation.createdAt) private var mutations: [PendingMutation]
    @Query(sort: \PendingImageUpload.createdAt) private var uploads: [PendingImageUpload]

    /// The row awaiting discard confirmation. Discarding a queued create throws away the only
    /// copy of that activity, so it asks first.
    @State private var discarding: QueueTarget?
    /// The stale-timer row awaiting "create without timer" confirmation. The original request may
    /// have already succeeded, so it warns about a possible duplicate first.
    @State private var creatingWithoutTimer: PendingMutation?
    /// The row to scroll to and outline on appear — the editor's sync banner lands here.
    var highlight: UUID? = nil

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            List {
                ForEach(mutations) { mutation in
                    let entity = LocalStore.fetch(localID: mutation.localID, in: context)
                    row(QueueRow(kind: mutation.kind,
                                 title: title(for: mutation),
                                 detail: entity.flatMap(EntityFormatting.subtitle),
                                 lastError: mutation.lastError,
                                 isBlocked: mutation.isBlocked,
                                 createdAt: mutation.createdAt,
                                 // A parked create with no `timer` field (the DELETE found the timer
                                 // gone) has nothing for the server to refuse: Retry would file the
                                 // duplicate unasked, so only "Create without timer" sends it.
                                 onRetry: mutation.isStaleTimer && !carriesTimer(mutation)
                                     ? nil : { sync.retry(mutation) },
                                 onCreateWithoutTimer: mutation.isStaleTimer
                                     ? { creatingWithoutTimer = mutation } : nil,
                                 highlighted: mutation.localID == highlight),
                        target: .mutation(mutation))
                    .id(mutation.localID)
                }
                ForEach(uploads) { upload in
                    let entity = LocalStore.fetch(localID: upload.localID, in: context)
                    row(QueueRow(kind: upload.kind,
                                 title: "\(upload.kind.displayName) photo",
                                 detail: entity.flatMap(EntityFormatting.subtitle),
                                 lastError: upload.lastError,
                                 isBlocked: upload.isBlocked,
                                 createdAt: upload.createdAt,
                                 onRetry: { sync.retry(upload) },
                                 onCreateWithoutTimer: nil,
                                 highlighted: false),
                        target: .upload(upload))
                }
            }
            .onAppear { if let highlight { proxy.scrollTo(highlight, anchor: .center) } }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(BBColor.surface)
            .navigationTitle("Pending Changes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .overlay {
                if mutations.isEmpty && uploads.isEmpty {
                    ContentUnavailableView("All Synced", systemImage: "checkmark.icloud",
                        description: Text("No changes are waiting to upload."))
                }
            }
            // `.alert`, not `confirmationDialog` — iOS 26 anchors the latter to its source as a
            // popover and drops the cancel action, leaving a destructive prompt with no way back.
            .alert("Discard this change?", isPresented: discardPrompt, presenting: discarding) { target in
                Button("Discard", role: .destructive) { discard(target) }
                Button("Cancel", role: .cancel) {}
            } message: { target in
                Text(discardWarning(target))
            }
            .alert("Create without the timer?", isPresented: createWithoutTimerPrompt,
                   presenting: creatingWithoutTimer) { mutation in
                Button("Create") { createWithoutTimer(mutation) }
                Button("Cancel", role: .cancel) {}
            } message: { mutation in
                Text("If this \(mutation.kind.displayName.lowercased()) was already saved when the timer was stopped, you'll end up with two copies. Check the server first if you're unsure.")
            }
        }
    }

    private func carriesTimer(_ mutation: PendingMutation) -> Bool {
        (try? JSONSerialization.jsonObject(with: mutation.payload) as? [String: Any])?["timer"] != nil
    }

    private var createWithoutTimerPrompt: Binding<Bool> {
        Binding(get: { creatingWithoutTimer != nil }, set: { if !$0 { creatingWithoutTimer = nil } })
    }

    private func createWithoutTimer(_ mutation: PendingMutation) {
        LocalRepository(context: context).createWithoutTimer(mutation)
        creatingWithoutTimer = nil
        Task { await sync.sync() }
    }

    @ViewBuilder
    private func row(_ content: QueueRow, target: QueueTarget) -> some View {
        content
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) { discarding = target } label: {
                    Label("Discard", systemImage: "trash")
                }
                .tint(BBColor.danger)
            }
    }

    private var discardPrompt: Binding<Bool> {
        Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })
    }

    private func discardWarning(_ target: QueueTarget) -> String {
        switch target {
        case .mutation(let mutation):
            switch mutation.op {
            case .create: return "This \(mutation.kind.displayName.lowercased()) never reached the server, so discarding it deletes it from this device too."
            case .update: return "Your unsaved edits are discarded and the record goes back to the server's version."
            case .delete: return "The record stays on the server and reappears on this device."
            }
        case .upload:
            return "The photo is removed from this device. Any photo already on the server is kept."
        }
    }

    private func discard(_ target: QueueTarget) {
        let repo = LocalRepository(context: context)
        switch target {
        case .mutation(let mutation): repo.discardPending(mutation)
        case .upload(let upload): repo.discardPendingImage(upload)
        }
        discarding = nil
    }

    /// What the queued write does, in plain words.
    private func title(for mutation: PendingMutation) -> String {
        let name = mutation.kind.displayName
        switch mutation.op {
        case .create: return "Added \(name)"
        case .update: return "Edited \(name)"
        case .delete: return "Deleted \(name)"
        }
    }

    /// Which queue row a confirmation is about. The two queues are separate models with separate
    /// discard semantics, so the prompt has to remember which one it's holding.
    private enum QueueTarget: Identifiable {
        case mutation(PendingMutation)
        case upload(PendingImageUpload)

        var id: UUID {
            switch self {
            case .mutation(let m): return m.id
            case .upload(let u): return u.id
            }
        }
    }
}

/// One queued item: tinted activity tile, what's waiting ("Added Feeding", "Child photo"), the
/// record's detail, when it was queued — and, when the server has refused it, why, plus the Retry
/// that is the only thing that will make sync pick it up again.
private struct QueueRow: View {
    let kind: EntityKind
    let title: String
    let detail: String?
    let lastError: String?
    let isBlocked: Bool
    let createdAt: Date
    let onRetry: (() -> Void)?
    /// Present only on a stale-timer create — the one blocked state with a second way out.
    let onCreateWithoutTimer: (() -> Void)?
    /// Outlined so the eye lands on it when arriving from the editor's sync banner.
    var highlighted: Bool = false

    var body: some View {
        BBCard(cornerRadius: BBRadius.row, padding: 13) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ActivityTile(kind: kind, size: 40, glyph: 21)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if let detail, !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        statusLine
                    }
                    Spacer(minLength: 8)
                    Text(createdAt, format: .relative(presentation: .named))
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
                if isBlocked {
                    HStack(spacing: 8) {
                        if let onRetry { action("Retry", systemImage: "arrow.clockwise", onRetry) }
                        if let onCreateWithoutTimer {
                            action("Create without timer", systemImage: "timer.slash", onCreateWithoutTimer)
                        }
                    }
                }
            }
        }
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: BBRadius.row, style: .continuous)
                    .strokeBorder(BBColor.danger, lineWidth: 2)
            }
        }
    }

    private func action(_ title: String, systemImage: String, _ perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(BBColor.brandTint, in: RoundedRectangle(
                    cornerRadius: BBRadius.control, style: .continuous))
                .foregroundStyle(BBColor.brandAccent)
        }
        .buttonStyle(.plain)
    }

    /// Blocked rows lead with the state, then the server's own words. A waiting row that has
    /// simply not gone out yet says so quietly; one that failed transiently still shows why.
    @ViewBuilder private var statusLine: some View {
        if isBlocked {
            Text("Needs attention")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(BBColor.danger)
        }
        if let lastError, !lastError.isEmpty {
            Text(lastError)
                .font(.caption)
                .foregroundStyle(isBlocked ? .primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !isBlocked {
            Text("Waiting to sync")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}

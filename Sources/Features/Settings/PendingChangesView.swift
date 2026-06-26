import SwiftUI
import SwiftData

/// The offline-first sync queue, laid bare: every write waiting to reach the server, oldest
/// first. Each row says what change is queued and shows the record's detail; swiping discards
/// it, reverting the cached record to the server's last-known state. It edits the *queue* —
/// it never opens the underlying record for editing.
struct PendingChangesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \PendingMutation.createdAt) private var mutations: [PendingMutation]

    var body: some View {
        NavigationStack {
            List {
                ForEach(mutations) { mutation in
                    PendingChangeRow(mutation: mutation,
                                     entity: LocalStore.fetch(localID: mutation.localID, in: context))
                        .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { discard(mutation) } label: {
                                Label("Discard", systemImage: "trash")
                            }
                            .tint(BBColor.danger)
                        }
                }
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
                if mutations.isEmpty {
                    ContentUnavailableView("All Synced", systemImage: "checkmark.icloud",
                        description: Text("No changes are waiting to upload."))
                }
            }
        }
    }

    private func discard(_ mutation: PendingMutation) {
        LocalRepository(context: context).discardPending(mutation)
    }
}

/// One queued change: tinted activity tile, what's waiting ("Added feeding"), the record's
/// detail, the time it was queued, and any delivery error.
private struct PendingChangeRow: View {
    let mutation: PendingMutation
    let entity: LocalEntity?

    var body: some View {
        BBCard(cornerRadius: BBRadius.row, padding: 13) {
            HStack(spacing: 12) {
                ActivityTile(kind: mutation.kind, size: 40, glyph: 21)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let detail, !detail.isEmpty {
                        Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    if let error = mutation.lastError {
                        Text(error).font(.caption2).foregroundStyle(BBColor.danger).lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                Text(mutation.createdAt, format: .relative(presentation: .named))
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    /// What the queued write does, in plain words.
    private var title: String {
        let name = mutation.kind.displayName
        switch mutation.op {
        case .create: return "Added \(name)"
        case .update: return "Edited \(name)"
        case .delete: return "Deleted \(name)"
        }
    }

    private var detail: String? {
        entity.flatMap(EntityFormatting.subtitle)
    }
}

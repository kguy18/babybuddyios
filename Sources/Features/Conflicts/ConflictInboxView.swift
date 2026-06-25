import SwiftUI
import SwiftData

/// Lists unresolved sync conflicts as Baby Buddy cards. Tapping one opens the resolution
/// screen. Each row reuses the activity tile + the shared `SyncStateBadge` conflicted style.
struct ConflictInboxView: View {
    @Query(sort: \ConflictRecord.detectedAt, order: .reverse) private var conflicts: [ConflictRecord]

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(conflicts) { conflict in
                    NavigationLink {
                        ConflictResolutionView(conflict: conflict)
                    } label: {
                        ConflictInboxRow(conflict: conflict)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(BBColor.surface)
        .navigationTitle("Conflicts")
        .overlay {
            if conflicts.isEmpty {
                ContentUnavailableView("No Conflicts", systemImage: "checkmark.circle",
                    description: Text("Everything is in sync."))
            }
        }
    }
}

/// A single conflict row: tinted activity tile, what happened, and the conflicted badge.
private struct ConflictInboxRow: View {
    let conflict: ConflictRecord

    var body: some View {
        BBCard(cornerRadius: BBRadius.row, padding: 13) {
            HStack(spacing: 12) {
                ActivityTile(kind: conflict.kind, size: 40, glyph: 21)
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.kind.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(conflict.serverDeleted
                         ? "Deleted on the server while you edited it"
                         : "Changed on the server and on this device")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 8)
                SyncStateBadge(state: .conflicted)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

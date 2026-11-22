import SwiftUI
import SwiftData

/// Lists unresolved sync conflicts as Baby Buddy cards. Tapping one opens the resolution
/// screen. Each row reuses the activity tile + the shared `SyncStateBadge` conflicted style.
struct ConflictInboxView: View {
    @Query(sort: \ConflictRecord.detectedAt, order: .reverse) private var conflicts: [ConflictRecord]

    var body: some View {
        FoldSplitView {
            if !conflicts.isEmpty {
                ScrollView {
                    Text("\(conflicts.count) to resolve")
                        .font(.title2.weight(.semibold))
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } main: { _ in
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
            .overlay {
                if conflicts.isEmpty {
                    ContentUnavailableView("No Conflicts", systemImage: "checkmark.circle",
                        description: Text("Everything is in sync."))
                }
            }
        }
        .background(BBColor.surface)
        .navigationTitle("Conflicts")
    }
}

/// A single conflict row: tinted activity tile, what happened, and the conflicted badge.
private struct ConflictInboxRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let conflict: ConflictRecord

    var body: some View {
        BBCard(cornerRadius: BBRadius.row, padding: 13) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 12))
            layout {
                if !typeSize.isAccessibilitySize {
                    ActivityTile(kind: conflict.kind, size: 40, glyph: 21)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(conflict.kind.displayName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(conflict.serverDeleted
                         ? String(localized: "Deleted on the server while you edited it")
                         : String(localized: "Changed on the server and on this device"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    SyncStateBadge(state: .conflicted)
                        .font(.body)
                        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
                    if typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens conflict resolution")
    }
}

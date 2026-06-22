import SwiftUI
import SwiftData

/// Merged chronological activity feed across all event kinds for the selected child,
/// grouped by day. Reads from the local cache.
struct TimelineView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @Binding var selectedChildID: Int

    @Query(sort: \LocalEntity.timestamp, order: .reverse) private var allEntities: [LocalEntity]
    @Query private var cachedTags: [CachedTag]
    @State private var kindFilter: EntityKind?
    @State private var editing: LocalEntity?

    /// Lowercased tag name → server `#RRGGBB` color, for tinting timeline chips.
    private var tagColors: [String: String] {
        Dictionary(
            cachedTags.compactMap { tag in tag.colorHex.map { (tag.name.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedDays, id: \.self) { day in
                    Section(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) {
                        ForEach(entities(on: day)) { entity in
                            TimelineRow(entity: entity, tagColors: tagColors)
                                .contentShape(Rectangle())
                                .onTapGesture { editing = entity }
                                .swipeActions {
                                    Button("Delete", role: .destructive) { delete(entity) }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ChildSwitcher(children: children, selectedChildID: $selectedChildID)
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .refreshable { await sync.sync() }
            .sheet(item: $editing) { entity in
                EntityEditorView(kind: entity.kind, childID: selectedChildID, entity: entity)
            }
            .overlay {
                if visibleEntities.isEmpty {
                    ContentUnavailableView("No Activity", systemImage: "list.bullet",
                        description: Text("Logged events will appear here."))
                }
            }
        }
    }

    private var filterMenu: some View {
        Menu {
            Button { kindFilter = nil } label: {
                Label("All", systemImage: kindFilter == nil ? "checkmark" : "line.3.horizontal.decrease")
            }
            ForEach(EntityKind.timelineKinds) { kind in
                Button { kindFilter = kind } label: {
                    Label {
                        Text(kind.displayName)
                    } icon: {
                        if kindFilter == kind { Image(systemName: "checkmark") } else { kind.icon() }
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    // MARK: Derived data

    private var children: [LocalEntity] { allEntities.filter { $0.kind == .child } }

    private var visibleEntities: [LocalEntity] {
        allEntities.filter {
            $0.childID == selectedChildID
                && $0.syncState != .pendingDelete
                && EntityKind.timelineKinds.contains($0.kind)
                && (kindFilter == nil || $0.kind == kindFilter)
        }
    }

    private func startOfDay(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    private var groupedDays: [Date] {
        Array(Set(visibleEntities.map { startOfDay($0.timestamp) })).sorted(by: >)
    }

    private func entities(on day: Date) -> [LocalEntity] {
        visibleEntities.filter { startOfDay($0.timestamp) == day }
    }

    private func delete(_ entity: LocalEntity) {
        LocalRepository(context: context).delete(entity)
        Task { await sync.sync() }
    }
}

private struct TimelineRow: View {
    let entity: LocalEntity
    let tagColors: [String: String]

    var body: some View {
        HStack(spacing: 12) {
            entity.kind.icon(22)
                .frame(width: 28)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(EntityFormatting.title(entity)).font(.body)
                if let subtitle = EntityFormatting.subtitle(entity), !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                let tags = EntityFormatting.tags(entity)
                if !tags.isEmpty {
                    FlowLayout(spacing: 4) {
                        ForEach(tags, id: \.self) { name in
                            TagChip(name: name, colorHex: tagColors[name.lowercased()],
                                    removable: false, compact: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(entity.timestamp, style: .time).font(.caption).foregroundStyle(.secondary)
                SyncStateBadge(state: entity.syncState).font(.caption2)
            }
        }
    }
}

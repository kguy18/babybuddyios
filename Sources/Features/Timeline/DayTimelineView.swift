import SwiftUI
import SwiftData

/// A focused, single-day slice of the timeline for one activity kind, pushed from a Dashboard
/// "Today" tile. Renders the same rail rows as the full ``TimelineView`` but is locked to one
/// kind on one day, with no filter/search/child-switch chrome. Reads from the local cache.
struct DayTimelineView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context

    let kind: EntityKind
    let childID: Int
    /// The day to scope to. Defaults to today; a parameter so it stays testable/previewable.
    var day: Date = .now

    @Query(sort: \LocalEntity.timestamp, order: .reverse) private var allEntities: [LocalEntity]
    @Query private var cachedTags: [CachedTag]
    @State private var editing: LocalEntity?
    @State private var adding = false

    /// Lowercased tag name → server `#RRGGBB` color, for tinting timeline chips.
    private var tagColors: [String: String] {
        Dictionary(
            cachedTags.compactMap { tag in tag.colorHex.map { (tag.name.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    /// This child's events of the scoped kind on the scoped day, newest first.
    private var events: [LocalEntity] {
        allEntities.filter {
            $0.kind == kind
                && $0.childID == childID
                && $0.syncState != .pendingDelete
                && Calendar.current.isDate($0.timestamp, inSameDayAs: day)
        }
    }

    var body: some View {
        List {
            ForEach(Array(events.enumerated()), id: \.element.localID) { index, entity in
                TimelineRailRow(entity: entity,
                                connectsDown: index < events.count - 1,
                                tagColors: tagColors)
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { editing = entity }
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button { repeatEvent(entity) } label: {
                            Label("Repeat", systemImage: "arrow.clockwise")
                        }
                        .tint(BBColor.repeatAction)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { delete(entity) } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .tint(BBColor.danger)
                        Button { editing = entity } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(BBColor.primary)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BBColor.surface)
        // Leave room so the last row can scroll clear of the floating add button.
        .contentMargins(.bottom, 88, for: .scrollContent)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await sync.sync() }
        .sheet(item: $editing) { entity in
            EntityEditorView(kind: entity.kind, childID: childID, entity: entity)
        }
        .sheet(isPresented: $adding) {
            // Log a new event of this view's kind. The editor self-gates premium kinds on create,
            // matching the Dashboard quick-add behavior.
            EntityEditorView(kind: kind, childID: childID)
        }
        .overlay {
            if events.isEmpty { emptyState }
        }
        .overlay(alignment: .bottomTrailing) {
            FloatingAddButton(accessibilityLabelText: "Add \(kind.displayName)") {
                adding = true
            }
            .padding(.trailing, 20)
            .padding(.bottom, 16)
        }
    }

    private var title: String {
        let when = Calendar.current.isDateInToday(day)
            ? "Today"
            : day.formatted(.dateTime.month(.abbreviated).day())
        return "\(kind.displayName) · \(when)"
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No \(kind.displayName)",
            systemImage: kind.systemImage,
            description: Text("No \(kind.displayName.lowercased()) logged for this day."))
    }

    // MARK: Mutations

    private func delete(_ entity: LocalEntity) {
        LocalRepository(context: context).delete(entity)
        Task { await sync.sync() }
    }

    private func repeatEvent(_ entity: LocalEntity) {
        LocalRepository(context: context).repeatEvent(entity)
        Task { await sync.sync() }
    }
}

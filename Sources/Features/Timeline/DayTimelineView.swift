import SwiftUI
import SwiftData

/// A focused, single-day slice of the timeline for one activity kind, pushed from a Dashboard
/// "Today" tile. Renders the same rail rows as the full ``TimelineView`` but is locked to one
/// kind on one day, with no filter/search/child-switch chrome. Reads from the local cache.
///
/// With no kind it lists every kind and is a pane rather than a screen: Home's side pane on iPhone
/// Duo's open display. It then has no title, "+" or undo toast of its own, since Home has them.
struct DayTimelineView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context

    let kind: EntityKind?
    let childID: Int
    /// The day to scope to. Defaults to today; a parameter so it stays testable/previewable.
    let day: Date
    /// Opens a tapped row's editor in the caller's sheet instead of this view's own.
    var onEdit: ((LocalEntity) -> Void)?

    /// This child's events of the scoped kind on the scoped day, newest first — filtered
    /// store-side so the view never materializes the whole table.
    @Query private var events: [LocalEntity]
    @Query private var cachedTags: [CachedTag]
    @Query(filter: #Predicate<PendingMutation> { $0.dispositionRaw != nil })
    private var blockedMutations: [PendingMutation]
    @State private var editing: LocalEntity?
    @State private var adding = false

    init(kind: EntityKind?, childID: Int, day: Date = .now, onEdit: ((LocalEntity) -> Void)? = nil) {
        self.kind = kind
        self.childID = childID
        self.day = day
        self.onEdit = onEdit
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? day
        let kinds = (kind.map { [$0] } ?? EntityKind.timelineKinds).map(\.rawValue)
        let pendingDelete = SyncState.pendingDelete.rawValue
        let predicate = #Predicate<LocalEntity> { entity in
            kinds.contains(entity.kindRaw) && entity.childID == childID
                && entity.syncStateRaw != pendingDelete
                && entity.timestamp >= dayStart && entity.timestamp < dayEnd
        }
        _events = Query(filter: predicate, sort: \LocalEntity.timestamp, order: .reverse)
    }

    /// Lowercased tag name → server `#RRGGBB` color, for tinting timeline chips.
    private var tagColors: [String: String] {
        Dictionary(
            cachedTags.compactMap { tag in tag.colorHex.map { (tag.name.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        List {
            if kind == nil {
                paneHeader
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(Array(events.enumerated()), id: \.element.localID) { index, entity in
                TimelineRailRow(entity: entity,
                                connectsDown: index < events.count - 1,
                                tagColors: tagColors,
                                blocked: blockedMutations.contains { $0.localID == entity.localID })
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { edit(entity) }
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
                        Button { edit(entity) } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(BBColor.primary)
                    }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BBColor.surface)
        .overlay(alignment: .bottom) {
            if kind != nil { UndoToastView().padding(.bottom, 12) }
        }
        // Leave room so the last row can scroll clear of the floating add button.
        .contentMargins(.bottom, kind == nil ? 0 : 88, for: .scrollContent)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await sync.sync() }
        .sheet(item: $editing) { entity in
            EntityEditorView(kind: entity.kind, childID: childID, entity: entity)
        }
        .sheet(isPresented: $adding) {
            // Log a new event of this view's kind.
            if let kind { EntityEditorView(kind: kind, childID: childID) }
        }
        .overlay {
            if events.isEmpty { emptyState }
        }
        .overlay(alignment: .bottomTrailing) {
            if let kind {
                FloatingAddButton(accessibilityLabelText: "Add \(kind.displayName)") {
                    adding = true
                }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private func edit(_ entity: LocalEntity) {
        if let onEdit { onEdit(entity) } else { editing = entity }
    }

    /// Empty for the pane, which sits on Home's own screen.
    private var title: String {
        guard let kind else { return "" }
        let when = Calendar.current.isDateInToday(day)
            ? "Today"
            : day.formatted(.dateTime.month(.abbreviated).day())
        return "\(kind.displayName) · \(when)"
    }

    /// "Today" over the day's counts, where a pushed day has its navigation title.
    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Today").font(.title3.weight(.semibold))
            Text([EntityKind.feeding, .change, .sleep]
                .map { "\(TodayTiles.label($0)) \(TodayTiles.value($0, today: events, unit: .region))" }
                .joined(separator: " · "))
                .font(.footnote).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var emptyState: some View {
        if let kind {
            ContentUnavailableView(
                "No \(kind.displayName)",
                systemImage: kind.systemImage,
                description: Text("No \(kind.displayName.lowercased()) logged for this day."))
        } else {
            ContentUnavailableView(
                "Nothing logged today", systemImage: "list.bullet",
                description: Text("What you log today shows here."))
        }
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

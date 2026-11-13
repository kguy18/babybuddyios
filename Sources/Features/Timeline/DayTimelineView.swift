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
    /// The record open right of the fold on iPhone Duo's open display.
    @State private var selected: LocalEntity?

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
        Group {
            if kind == nil {
                list(split: false)
            } else {
                // On iPhone Duo's open display the list goes left of the fold and the tapped record
                // opens right of it, as on the Timeline tab.
                FoldSplitView {
                    list(split: true)
                } main: { split in
                    Group {
                        if split { detailPane } else { list(split: false) }
                    }
                    // Folding the phone with a record open carries it into the editor sheet.
                    .onChange(of: split) { _, split in
                        if !split, let selected {
                            editing = selected
                            self.selected = nil
                        }
                    }
                }
            }
        }
        .background(BBColor.surface)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { entity in
            EntityEditorView(kind: entity.kind, childID: childID, entity: entity)
        }
        .sheet(isPresented: $adding) {
            // Log a new event of this view's kind.
            if let kind { EntityEditorView(kind: kind, childID: childID) }
        }
    }

    /// The rows. `split` is the open display's left pane, where a tap opens the record right of
    /// the fold and the open record's row is highlighted.
    private func list(split: Bool) -> some View {
        List {
            if kind == nil {
                paneHeader
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            if events.isEmpty {
                // Under the header rather than over the list, where it drew across the header.
                emptyState
                    // Without it the row is sized too short at the largest text, and the title
                    // is cut off on one line instead of wrapping.
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(Array(events.enumerated()), id: \.element.localID) { index, entity in
                let isOpen = split && selected?.localID == entity.localID
                TimelineRailRow(entity: entity,
                                connectsDown: index < events.count - 1,
                                tagColors: tagColors,
                                blocked: blockedMutations.contains { $0.localID == entity.localID })
                    .accessibilityAddTraits(isOpen ? .isSelected : [])
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(isOpen ? BBColor.brandTint : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { open(entity, split: split) }
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
                        Button { open(entity, split: split) } label: {
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
        .refreshable { await sync.sync() }
        .overlay(alignment: .bottomTrailing) {
            if let kind {
                FloatingAddButton(accessibilityLabelText: String(localized: "Add \(kind.displayName)")) {
                    adding = true
                }
                .padding(.trailing, 20)
                .padding(.bottom, 16)
            }
        }
    }

    private func open(_ entity: LocalEntity, split: Bool) {
        if split { selected = entity } else { edit(entity) }
    }

    private func edit(_ entity: LocalEntity) {
        if let onEdit { onEdit(entity) } else { editing = entity }
    }

    /// Right of the fold: the open record's editor, or a prompt to pick one. A record that has
    /// gone, deleted here or by a sync, closes its editor.
    @ViewBuilder private var detailPane: some View {
        if let selected, events.contains(where: { $0.localID == selected.localID }) {
            EntityEditorView(kind: selected.kind, childID: childID, entity: selected,
                             onClose: { self.selected = nil })
                .id(selected.localID)
        } else {
            ContentUnavailableView("No activity open", systemImage: "list.bullet",
                                   description: Text("Tap an activity on the left to edit it here."))
        }
    }

    /// Empty for the pane, which sits on Home's own screen.
    private var title: String {
        guard let kind else { return "" }
        let when = Calendar.current.isDateInToday(day)
            ? String(localized: "Today")
            : day.formatted(.dateTime.month(.abbreviated).day())
        return String(localized: "\(kind.displayName) · \(when)")
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
                description: Text("No \(kind.sentenceName) logged for this day."))
        } else {
            ContentUnavailableView(
                "Nothing logged today", systemImage: "list.bullet",
                description: Text("What you log today shows here."))
        }
    }

    // MARK: Mutations

    private func delete(_ entity: LocalEntity) {
        if selected?.localID == entity.localID { selected = nil }
        LocalRepository(context: context).delete(entity)
        Task { await sync.sync() }
    }

    private func repeatEvent(_ entity: LocalEntity) {
        LocalRepository(context: context).repeatEvent(entity)
        Task { await sync.sync() }
    }
}

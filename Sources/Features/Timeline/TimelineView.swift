import SwiftUI
import SwiftData

/// Merged chronological activity feed across all event kinds for the selected child, grouped
/// by day and laid out as a continuous left "rail": each event's tinted glyph tile is a node
/// on a spine that resets at every day boundary. Reads from the local cache.
struct TimelineView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(DeepLinkRouter.self) private var router
    @Binding var selectedChildID: Int

    /// The selected child's timeline events, filtered store-side (child, kind, delete state) so
    /// the view never materializes the whole table. Rebuilt on child switch via `init`.
    @Query private var events: [LocalEntity]
    @Query(filter: #Predicate<LocalEntity> { $0.kindRaw == "child" }, sort: \.timestamp)
    private var children: [LocalEntity]
    @Query private var cachedTags: [CachedTag]
    /// Rows whose queued write the server refused, so the timeline can flag them.
    @Query(filter: #Predicate<PendingMutation> { $0.dispositionRaw != nil })
    private var blockedMutations: [PendingMutation]
    private var blockedIDs: Set<UUID> { Set(blockedMutations.map(\.localID)) }
    @State private var kindFilter: EntityKind?
    @State private var editing: LocalEntity?
    /// The record open in the right pane on iPhone Duo's open display.
    @State private var selected: LocalEntity?
    @State private var didAutoLoadHistory = false
    @State private var searchText = ""
    @State private var dateFrom: Date?
    @State private var dateTo: Date?
    @State private var showingFilters = false
    @State private var searchActive = false
    @State private var searchDebounce: Task<Void, Never>?
    @Environment(\.dynamicTypeSize) private var typeSize

    init(selectedChildID: Binding<Int>) {
        _selectedChildID = selectedChildID
        let child = selectedChildID.wrappedValue
        let kinds = EntityKind.timelineKinds.map(\.rawValue)
        let pendingDelete = SyncState.pendingDelete.rawValue
        let predicate = #Predicate<LocalEntity> { entity in
            entity.childID == child && kinds.contains(entity.kindRaw)
                && entity.syncStateRaw != pendingDelete
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
        // One evaluation per body pass: the item list (filter + group + summarize in a single
        // sweep) and the tag-color map both used to be computed properties re-evaluated per
        // reference, which multiplied the whole filter chain by the number of days on screen.
        let items = timelineItems
        let tagColors = self.tagColors
        NavigationStack {
            // On iPhone Duo's open display the list goes left of the fold and the tapped record
            // opens right of it, ready to edit. Everywhere else the list is the whole screen.
            FoldSplitView {
                list(items, tagColors: tagColors, split: true)
                    .safeAreaInset(edge: .top, spacing: 0) { paneHeader }
            } main: { split in
                Group {
                    if split {
                        detailPane
                    } else {
                        // Split, the search field and the child pill are in the left pane's
                        // header instead: in the navigation bar they ran across the fold.
                        list(items, tagColors: tagColors, split: false)
                            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always),
                                        prompt: String(localized: "Search notes, tags, type…"))
                    }
                }
                .navigationTitle("Timeline")
                .toolbar {
                    if split {
                        // The bar keeps its title, which names the screen to VoiceOver, but shows
                        // nothing: in the middle of the bar it would sit on the fold.
                        ToolbarItem(placement: .principal) {
                            Color.clear.frame(width: 1, height: 1).accessibilityHidden(true)
                        }
                    } else {
                        ChildSwitcher(children: children, selectedChildID: $selectedChildID)
                        ToolbarItem(placement: .topBarTrailing) { filterButton }
                    }
                }
                // Folding the phone with a record open carries it into the phone's editor sheet.
                .onChange(of: split) { _, split in
                    if !split, let selected {
                        editing = selected
                        self.selected = nil
                    }
                }
            }
            .background(BBColor.surface)
            .accessibilityIdentifier("screen-timeline")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: searchText) { _, newValue in handleSearchChange(newValue) }
            .onAppear(perform: autoLoadOlderIfRequested)
            .onAppear { applyRequestedKind(router.showTimelineKind) }
            .onChange(of: router.showTimelineKind) { _, kind in applyRequestedKind(kind) }
            .sheet(item: $editing) { entity in
                EntityEditorView(kind: entity.kind, childID: selectedChildID, entity: entity)
            }
            .sheet(isPresented: $showingFilters) {
                TimelineFiltersView(kindFilter: $kindFilter, dateFrom: $dateFrom, dateTo: $dateTo)
            }
        }
    }

    /// The day-grouped rows. `split` is the open display's left pane, where a tap opens the record
    /// in the right pane instead of a sheet, and the open record's row is highlighted.
    private func list(_ items: [TimelineItem], tagColors: [String: String], split: Bool) -> some View {
        List {
            if items.isEmpty {
                // In the list rather than over it, so it scrolls clear of the keyboard.
                emptyState
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
            ForEach(items) { item in
                switch item {
                case .header(let day, let summary):
                    dayHeader(day, summary: summary)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                case .event(let entity, let connectsDown):
                    let isOpen = split && selected?.localID == entity.localID
                    TimelineRailRow(entity: entity, connectsDown: connectsDown, tagColors: tagColors,
                                    blocked: blockedIDs.contains(entity.localID))
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
            if showHistoryFooter(items) {
                historyFooter
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(BBColor.surface)
        .overlay(alignment: .bottom) { UndoToastView().padding(.bottom, 12) }
        .refreshable { await sync.sync() }
    }

    private func open(_ entity: LocalEntity, split: Bool) {
        if split { selected = entity } else { editing = entity }
    }

    /// The left pane's own title bar, with the filter button, the child pill and the search field:
    /// on iPhone Duo only the right pane's actions go in the rail, and the navigation bar's search
    /// field and pill ran across the fold.
    private var paneHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timeline").font(.title3.weight(.bold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                filterButton.font(.title3)
            }
            // Neutral, as in the navigation bar: in a pane the menu's label would take the tint.
            ChildPill(children: children, selectedChildID: $selectedChildID).tint(.primary)
            searchField
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(BBColor.surface)
    }

    /// The left pane's search field, on the same text as the navigation bar's.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search notes, tags, type…", text: $searchText)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .accessibilityLabel("Clear text")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(BBColor.controlFill, in: Capsule())
    }

    /// Right of the fold: the open record's editor, or a prompt to pick one. A record that has
    /// gone, deleted here or by a sync, closes its editor.
    @ViewBuilder private var detailPane: some View {
        if let selected, events.contains(where: { $0.localID == selected.localID }) {
            EntityEditorView(kind: selected.kind, childID: selectedChildID, entity: selected,
                             onClose: { self.selected = nil })
                .id(selected.localID)
        } else {
            ContentUnavailableView("No activity open", systemImage: "list.bullet",
                                   description: Text("Tap an activity on the left to edit it here."))
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isFilteringOrSearching {
            ContentUnavailableView {
                // The icon would push the Clear button under the keyboard. A bare Text gets the
                // title's size but not its weight, which only a Label gets.
                if typeSize.isAccessibilitySize {
                    Text("No Results").bold()
                } else {
                    Label("No Results", systemImage: "magnifyingglass")
                }
            } description: {
                Text("No activity matches your search and filters.")
            } actions: {
                // Borderless keeps the tint: in a list row a plain button takes the row's style.
                Button("Clear Search & Filters") { clearAllFilters() }
                    .buttonStyle(.borderless)
            }
        } else {
            ContentUnavailableView("No Activity", systemImage: "list.bullet",
                description: Text("Logged events will appear here."))
        }
    }

    // MARK: History footer

    /// Show the "load older" affordance only when there's activity to anchor it and there's
    /// either more history to fetch or a fetch in progress.
    private func showHistoryFooter(_ items: [TimelineItem]) -> Bool {
        !items.isEmpty && (sync.hasMoreHistory || sync.isLoadingHistory)
    }

    /// DEBUG-only: `BB_LOAD_OLDER=<n>` auto-pages history `n` times on first appearance, so the
    /// load-older merge can be verified deterministically in the simulator via screenshots
    /// (alongside `BB_DEMO`). Runs once per view lifetime.
    private func autoLoadOlderIfRequested() {
        #if DEBUG
        guard !didAutoLoadHistory,
              let n = ProcessInfo.processInfo.environment["BB_LOAD_OLDER"].flatMap(Int.init), n > 0
        else { return }
        didAutoLoadHistory = true
        Task { for _ in 0..<n { await sync.loadOlderHistory() } }
        #endif
    }

    @ViewBuilder
    private var historyFooter: some View {
        VStack(spacing: 8) {
            if sync.isLoadingHistory {
                ProgressView()
                Text("Loading older activity…")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Button { Task { await sync.loadOlderHistory() } } label: {
                    Label("Load older activity", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.medium))
                }
                .buttonStyle(.bordered)
                .tint(BBColor.primary)
                if let error = sync.historyError {
                    Text(error)
                        .font(.caption).foregroundStyle(BBColor.danger)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: Day header

    /// The day over its summary at accessibility sizes, where side by side the summary truncated.
    private func dayHeader(_ day: Date, summary: String) -> some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return layout {
            Text(dayLabel(day))
                .font(.subheadline.weight(.semibold))
            if !stacked { Spacer(minLength: 8) }
            Text(summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(stacked ? nil : 1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
    }

    private var filterButton: some View {
        Button { showingFilters = true } label: {
            Image(systemName: hasActiveFilters
                  ? "line.3.horizontal.decrease.circle.fill"
                  : "line.3.horizontal.decrease.circle")
        }
        .accessibilityLabel("Filters")
    }

    // MARK: Derived data

    /// The selected child's display name, included in the search haystack so activity can be
    /// found by child even though the payload only carries the child's id.
    private var selectedChildName: String? {
        guard let child = children.first(where: { $0.serverID == selectedChildID }) else { return nil }
        let p = child.payloadObject
        let parts = [p["first_name"] as? String, p["last_name"] as? String]
            .compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// The store-side query already scoped to child/kind/delete-state; this applies the cheap
    /// user filters (kind picker, date range) before the substring search, so the haystack is
    /// only built for the already-narrowed set.
    private var visibleEntities: [LocalEntity] {
        let childName = selectedChildName
        return events.filter {
            (kindFilter == nil || $0.kind == kindFilter)
                && TimelineFiltering.inDateRange($0.timestamp, from: dateFrom, to: dateTo)
                && TimelineFiltering.matchesSearch($0, query: searchText, childName: childName)
        }
    }

    private var hasActiveFilters: Bool { kindFilter != nil || dateFrom != nil || dateTo != nil }

    private var isFilteringOrSearching: Bool {
        hasActiveFilters || !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// A Latest row on Home asked for this kind: filter to it alone, replacing whatever was set.
    private func applyRequestedKind(_ kind: EntityKind?) {
        guard let kind else { return }
        clearAllFilters()
        kindFilter = kind
        router.showTimelineKind = nil
    }

    private func clearAllFilters() {
        kindFilter = nil
        dateFrom = nil
        dateTo = nil
        searchText = ""
    }

    /// Emits `Search` analytics: `started` once when a query begins, then `completed` or
    /// `no-results` after typing settles (debounced, so we don't signal per keystroke).
    /// `visibleEntities` already reflects `newValue` here since `onChange` fires post-update.
    private func handleSearchChange(_ text: String) {
        searchDebounce?.cancel()
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchActive = false
            return
        }
        if !searchActive {
            searchActive = true
            Analytics.search(.started)
        }
        let isEmpty = visibleEntities.isEmpty
        searchDebounce = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            Analytics.search(isEmpty ? .noResults : .completed)
        }
    }

    private func startOfDay(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    /// Flattened header + event rows, in display order, with each day's summary precomputed.
    /// Each event knows whether the spine continues below it (true for every event except the
    /// day's last/oldest). Built in one linear sweep: `visibleEntities` is sorted newest-first,
    /// so a day's events are contiguous — no per-day refiltering.
    private var timelineItems: [TimelineItem] {
        let visible = visibleEntities
        var result: [TimelineItem] = []
        result.reserveCapacity(visible.count + 16)
        var index = 0
        while index < visible.count {
            let day = startOfDay(visible[index].timestamp)
            let dayStart = index
            while index < visible.count, startOfDay(visible[index].timestamp) == day { index += 1 }
            let dayEvents = Array(visible[dayStart..<index])
            result.append(.header(day, summary: daySummary(dayEvents)))
            for (offset, entity) in dayEvents.enumerated() {
                result.append(.event(entity, connectsDown: offset < dayEvents.count - 1))
            }
        }
        return result
    }

    // MARK: Day labels & summary

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return String(localized: "Today") }
        if cal.isDateInYesterday(day) { return String(localized: "Yesterday") }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// One-line tally for a day's events (e.g. "6 feeds · 5h 20m sleep · 4 diapers").
    private func daySummary(_ events: [LocalEntity]) -> String {
        var parts: [String] = []

        let feeds = events.filter { $0.kind == .feeding }.count
        if feeds > 0 { parts.append(String(localized: "\(feeds) feeds")) }

        let sleep = totalDuration(events, kind: .sleep)
        if sleep > 0 { parts.append(String(localized: "\(EntityFormatting.formatInterval(sleep)) sleep")) }

        let diapers = events.filter { $0.kind == .change }.count
        if diapers > 0 { parts.append(String(localized: "\(diapers) diapers")) }

        if parts.isEmpty {
            let n = events.count
            return String(localized: "\(n) events")
        }
        return parts.joined(separator: " · ")
    }

    /// Summed start→end duration across the day's events of one kind.
    private func totalDuration(_ events: [LocalEntity], kind: EntityKind) -> TimeInterval {
        events.filter { $0.kind == kind }.reduce(0) { acc, e in
            let dates = e.startEndDates
            if let start = dates.start, let end = dates.end, end > start {
                return acc + end.timeIntervalSince(start)
            }
            return acc
        }
    }

    // MARK: Mutations

    private func delete(_ entity: LocalEntity) {
        if selected?.localID == entity.localID { selected = nil }
        LocalRepository(context: context).delete(entity)
        Task { await sync.sync() }
    }

    /// Re-log an event as a fresh record stamped to now (see ``LocalRepository/repeatEvent(_:now:)``).
    private func repeatEvent(_ entity: LocalEntity) {
        LocalRepository(context: context).repeatEvent(entity)
        Task { await sync.sync() }
    }
}

/// A header or an event in the flattened, day-grouped timeline. The header carries its
/// precomputed summary line so rendering never refilters the day's events.
private enum TimelineItem: Identifiable {
    case header(Date, summary: String)
    case event(LocalEntity, connectsDown: Bool)

    var id: String {
        switch self {
        case .header(let day, _): return "h-\(day.timeIntervalSince1970)"
        case .event(let entity, _): return "e-\(entity.localID.uuidString)"
        }
    }
}

/// One event on the rail: a tinted glyph node on the spine, beside its detail card.
/// Shared with ``DayTimelineView`` so scoped day slices render identical rows.
struct TimelineRailRow: View {
    let entity: LocalEntity
    let connectsDown: Bool
    let tagColors: [String: String]
    var blocked: Bool = false
    /// Watched so a temperature redraws in a unit picked in Settings.
    @AppStorage(TemperatureUnit.key, store: SharedDefaults.suite) private var unit: TemperatureUnit?
    /// At accessibility sizes the time goes under the title: beside it, both broke mid-word.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            RailNode(kind: entity.kind, connectsDown: connectsDown)
            card.padding(.bottom, 9)
        }
        .padding(.horizontal, 16)
        // One combined element; the row's tap (edit) and swipe actions stay reachable via VoiceOver.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowLabel)
        .accessibilityHint("Opens the editor")
        .accessibilityAddTraits(.isButton)
    }

    private var rowLabel: String {
        var label = EntityFormatting.accessibilityLabel(entity, blocked: blocked)
        if noteImageURL != nil { label += ", photo attached" }
        if let next = nextDose { label += ", next dose OK at \(next.formatted(date: .omitted, time: .shortened))" }
        return label
    }

    /// When a medication's next dose is OK, while that is still ahead.
    private var nextDose: Date? {
        MedicationReminderPolicy.nextDose(after: entity).flatMap { $0 > .now ? $0 : nil }
    }

    /// A note's attached image URL, if this row is a note with an image set.
    private var noteImageURL: String? {
        guard entity.kind == .note, let url = entity.payloadObject["image"] as? String, !url.isEmpty
        else { return nil }
        return url
    }

    private var card: some View {
        BBCard(cornerRadius: BBRadius.tile, padding: 13) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(EntityFormatting.title(entity))
                        .font(.subheadline.weight(.semibold))
                    if typeSize.isAccessibilitySize {
                        HStack(spacing: 6) { time }.padding(.top, 2)
                    }
                    if let subtitle = EntityFormatting.subtitle(entity, unit: unit ?? .region), !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption).foregroundStyle(.secondary)
                            .lineLimit(typeSize.isAccessibilitySize ? 3 : 1)
                            .padding(.top, 2)
                    }
                    if let nextDose {
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text("Next dose OK at \(nextDose.formatted(date: .omitted, time: .shortened))")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                    let tags = EntityFormatting.tags(entity)
                    if !tags.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(tags, id: \.self) { name in
                                TagDotChip(name: name, colorHex: tagColors[name.lowercased()])
                            }
                        }
                        .padding(.top, 7)
                    }
                }
                if let noteImageURL {
                    RemoteImage(urlString: noteImageURL) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(BBColor.controlFill)
                            .overlay(Image(systemName: "photo")
                                .font(.caption).foregroundStyle(.secondary))
                    }
                    .frame(width: 46, height: 46)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.leading, 4)
                }
                if !typeSize.isAccessibilitySize {
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 2) { time }
                }
            }
        }
    }

    @ViewBuilder private var time: some View {
        Text(entity.timestamp.formatted(date: .omitted, time: .shortened))
            .font(.subheadline.weight(.semibold)).monospacedDigit()
        SyncStateBadge(state: entity.syncState, blocked: blocked).font(.caption2)
    }
}

/// The 40pt rail column: the activity's glyph tile as a node, plus a 2pt spine descending to
/// the next node (drawn only when the spine continues — the day's last event has none).
private struct RailNode: View {
    // Matches ActivityTile's Dynamic-Type scaling so the column widens with the tile instead of
    // clipping the glyph at large accessibility text sizes.
    @ScaledMetric(relativeTo: .body) private var typeScale: CGFloat = 1
    let kind: EntityKind
    let connectsDown: Bool

    private var columnWidth: CGFloat { 40 * min(typeScale, 1.6) }

    var body: some View {
        ActivityTile(kind: kind, size: 38, glyph: 20)
            .padding(.top, 5)
            .frame(width: columnWidth, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(alignment: .top) {
                if connectsDown {
                    Rectangle()
                        .fill(BBColor.railLine)
                        .frame(width: 2)
                        .padding(.top, columnWidth + 3)
                }
            }
    }
}

/// Sheet for the timeline's activity-type and date-range filters. Bindings write straight back
/// to the timeline, so changes apply live behind the sheet; combines with the search field.
private struct TimelineFiltersView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var kindFilter: EntityKind?
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Environment(\.dynamicTypeSize) private var typeSize

    private var hasActiveFilters: Bool { kindFilter != nil || dateFrom != nil || dateTo != nil }

    /// Default seed when a date bound is first enabled: 30 days back for "from", today for "to".
    private var defaultFrom: Date {
        Calendar.current.date(byAdding: .day, value: -30, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity Type") {
                    Picker("Type", selection: $kindFilter) {
                        Text("All Types").tag(EntityKind?.none)
                        ForEach(EntityKind.timelineKinds) { kind in
                            Text(kind.displayName).tag(EntityKind?.some(kind))
                        }
                    }
                }
                Section("Date Range") {
                    dateBound(label: String(localized: "From"), date: $dateFrom, default: defaultFrom)
                    dateBound(label: String(localized: "To"), date: $dateTo, default: Calendar.current.startOfDay(for: .now))
                }
                if hasActiveFilters {
                    Section {
                        Button("Clear Filters", role: .destructive) {
                            kindFilter = nil; dateFrom = nil; dateTo = nil
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        // Full height at accessibility sizes: at half height the date range was cut off.
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }

    /// A toggle that enables/clears an optional date bound, plus a date picker shown when on.
    @ViewBuilder
    private func dateBound(label: String, date: Binding<Date?>, default seed: Date) -> some View {
        Toggle(label, isOn: Binding(
            get: { date.wrappedValue != nil },
            set: { date.wrappedValue = $0 ? seed : nil }))
        if date.wrappedValue != nil {
            DatePicker(label, selection: Binding(
                get: { date.wrappedValue ?? seed },
                set: { date.wrappedValue = $0 }),
                displayedComponents: .date)
            .labelsHidden()
        }
    }
}

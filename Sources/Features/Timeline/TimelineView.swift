import SwiftUI
import SwiftData

/// Merged chronological activity feed across all event kinds for the selected child, grouped
/// by day and laid out as a continuous left "rail": each event's tinted glyph tile is a node
/// on a spine that resets at every day boundary. Reads from the local cache.
struct TimelineView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @Binding var selectedChildID: Int

    @Query(sort: \LocalEntity.timestamp, order: .reverse) private var allEntities: [LocalEntity]
    @Query private var cachedTags: [CachedTag]
    @State private var kindFilter: EntityKind?
    @State private var editing: LocalEntity?
    @State private var didAutoLoadHistory = false

    /// Lowercased tag name → server `#RRGGBB` color, for tinting timeline chips.
    private var tagColors: [String: String] {
        Dictionary(
            cachedTags.compactMap { tag in tag.colorHex.map { (tag.name.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(timelineItems) { item in
                    switch item {
                    case .header(let day):
                        dayHeader(day)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    case .event(let entity, let connectsDown):
                        TimelineRailRow(entity: entity, connectsDown: connectsDown, tagColors: tagColors)
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
                if showHistoryFooter {
                    historyFooter
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(BBColor.surface)
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ChildSwitcher(children: children, selectedChildID: $selectedChildID)
                ToolbarItem(placement: .topBarTrailing) { filterMenu }
            }
            .refreshable { await sync.sync() }
            .onAppear(perform: autoLoadOlderIfRequested)
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

    // MARK: History footer

    /// Show the "load older" affordance only when there's activity to anchor it and there's
    /// either more history to fetch or a fetch in progress.
    private var showHistoryFooter: Bool {
        !visibleEntities.isEmpty && (sync.hasMoreHistory || sync.isLoadingHistory)
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

    private func dayHeader(_ day: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(dayLabel(day))
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(daySummary(day))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
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

    /// Flattened header + event rows, in display order. Each event knows whether the spine
    /// continues below it (true for every event except the day's last/oldest).
    private var timelineItems: [TimelineItem] {
        var result: [TimelineItem] = []
        for day in groupedDays {
            result.append(.header(day))
            let dayEvents = entities(on: day)
            for (index, entity) in dayEvents.enumerated() {
                result.append(.event(entity, connectsDown: index < dayEvents.count - 1))
            }
        }
        return result
    }

    // MARK: Day labels & summary

    private func dayLabel(_ day: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(day) { return "Today" }
        if cal.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    /// One-line tally for the day header (e.g. "6 feeds · 5h 20m sleep · 4 diapers").
    private func daySummary(_ day: Date) -> String {
        let events = entities(on: day)
        var parts: [String] = []

        let feeds = events.filter { $0.kind == .feeding }.count
        if feeds > 0 { parts.append("\(feeds) feed\(feeds == 1 ? "" : "s")") }

        let sleep = totalDuration(events, kind: .sleep)
        if sleep > 0 { parts.append("\(EntityFormatting.formatInterval(sleep)) sleep") }

        let diapers = events.filter { $0.kind == .change }.count
        if diapers > 0 { parts.append("\(diapers) diaper\(diapers == 1 ? "" : "s")") }

        if parts.isEmpty {
            let n = events.count
            return "\(n) event\(n == 1 ? "" : "s")"
        }
        return parts.joined(separator: " · ")
    }

    /// Summed start→end duration across the day's events of one kind.
    private func totalDuration(_ events: [LocalEntity], kind: EntityKind) -> TimeInterval {
        events.filter { $0.kind == kind }.reduce(0) { acc, e in
            let p = e.payloadObject
            if let s = p["start"] as? String, let en = p["end"] as? String,
               let start = APIDate.parse(s), let end = APIDate.parse(en), end > start {
                return acc + end.timeIntervalSince(start)
            }
            return acc
        }
    }

    // MARK: Mutations

    private func delete(_ entity: LocalEntity) {
        LocalRepository(context: context).delete(entity)
        Task { await sync.sync() }
    }

    /// Re-log an event as a fresh record at the current time: copy its payload, drop the
    /// server-assigned/computed fields, and re-stamp the timestamps to now (preserving an
    /// activity's duration). Uses the existing repository create path — no model changes.
    private func repeatEvent(_ entity: LocalEntity) {
        var p = entity.payloadObject
        for key in ["id", "url", "duration"] { p.removeValue(forKey: key) }

        let now = Date()
        func iso(_ d: Date) -> String { APIDate.isoDateTime.string(from: d) }
        if let s = p["start"] as? String, let e = p["end"] as? String,
           let start = APIDate.parse(s), let end = APIDate.parse(e), end > start {
            let duration = end.timeIntervalSince(start)
            p["start"] = iso(now.addingTimeInterval(-duration))
            p["end"] = iso(now)
        } else if p["start"] is String {
            p["start"] = iso(now)
        }
        if p["time"] is String { p["time"] = iso(now) }
        if p["date"] is String { p["date"] = APIDate.dateOnly.string(from: now) }

        LocalRepository(context: context).create(kind: entity.kind, payload: p)
        Task { await sync.sync() }
    }
}

/// A header or an event in the flattened, day-grouped timeline.
private enum TimelineItem: Identifiable {
    case header(Date)
    case event(LocalEntity, connectsDown: Bool)

    var id: String {
        switch self {
        case .header(let day): return "h-\(day.timeIntervalSince1970)"
        case .event(let entity, _): return "e-\(entity.localID.uuidString)"
        }
    }
}

/// One event on the rail: a tinted glyph node on the spine, beside its detail card.
private struct TimelineRailRow: View {
    let entity: LocalEntity
    let connectsDown: Bool
    let tagColors: [String: String]

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            RailNode(kind: entity.kind, connectsDown: connectsDown)
            card.padding(.bottom, 9)
        }
        .padding(.horizontal, 16)
    }

    private var card: some View {
        BBCard(cornerRadius: BBRadius.tile, padding: 13) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(EntityFormatting.title(entity))
                        .font(.subheadline.weight(.semibold))
                    if let subtitle = EntityFormatting.subtitle(entity), !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
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
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entity.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                    SyncStateBadge(state: entity.syncState).font(.caption2)
                }
            }
        }
    }
}

/// The 40pt rail column: the activity's glyph tile as a node, plus a 2pt spine descending to
/// the next node (drawn only when the spine continues — the day's last event has none).
private struct RailNode: View {
    let kind: EntityKind
    let connectsDown: Bool

    var body: some View {
        ActivityTile(kind: kind, size: 38, glyph: 20)
            .padding(.top, 5)
            .frame(width: 40, alignment: .top)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(alignment: .top) {
                if connectsDown {
                    Rectangle()
                        .fill(BBColor.railLine)
                        .frame(width: 2)
                        .padding(.top, 43)
                }
            }
    }
}

import SwiftUI
import SwiftData

/// Baby Buddy-style overview: active timer hero, today's running totals, and the most-recent
/// event of each kind for the selected child. Reads entirely from the local cache.
struct DashboardView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(DeepLinkRouter.self) private var router
    @Binding var selectedChildID: Int

    @Query(sort: \LocalEntity.timestamp, order: .reverse) private var allEntities: [LocalEntity]
    @State private var addKind: EntityKind?
    @State private var editing: LocalEntity?
    @State private var startingTimer = false
    @State private var quickAddOpen = false
    @State private var showAllActivities = false
    /// A kind chosen from the "More" sheet, opened in the editor once that sheet has dismissed
    /// (so the editor doesn't try to present while another sheet is still on screen).
    @State private var pendingAddKind: EntityKind?
    @State private var stoppingTimer: LocalEntity?
    @State private var convertRequest: ConvertRequest?
    /// A convert deferred until the Stop sheet finishes dismissing, so the detail editor doesn't
    /// try to present while another sheet is still on screen.
    @State private var pendingConvert: ConvertRequest?

    /// A request to convert a specific timer into a specific activity kind.
    private struct ConvertRequest: Identifiable {
        let timer: LocalEntity
        let kind: EntityKind
        var id: String { "\(timer.localID)-\(kind.rawValue)" }
    }

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    private let recentKinds: [EntityKind] = [.feeding, .change, .sleep, .tummyTime, .pumping]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    header

                    if activeTimers.isEmpty {
                        startTimerCard
                    } else {
                        VStack(spacing: 12) {
                            ForEach(activeTimers) { timerHero($0) }
                        }
                    }

                    todaySection
                    if !latestEvents.isEmpty { latestSection }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                // Leave room so the last row can scroll clear of the floating add button.
                .padding(.bottom, 88)
            }
            .background(BBColor.surface)
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: EntityKind.self) { kind in
                DayTimelineView(kind: kind, childID: selectedChildID)
            }
            .overlay {
                if !children.isEmpty {
                    QuickAddMenu(
                        isOpen: $quickAddOpen,
                        onStartTimer: { startingTimer = true },
                        onLog: { addKind = $0 },
                        onMore: { showAllActivities = true })
                }
            }
            .sheet(item: $addKind) { kind in
                EntityEditorView(kind: kind, childID: selectedChildID)
            }
            .sheet(isPresented: $showAllActivities, onDismiss: {
                // Open the editor only after the "More" sheet is fully gone.
                if let pendingAddKind { addKind = pendingAddKind; self.pendingAddKind = nil }
            }) {
                AllActivitiesSheet(onPick: { kind in pendingAddKind = kind; showAllActivities = false })
            }
            .sheet(item: $editing) { entity in
                EntityEditorView(kind: entity.kind, childID: selectedChildID, entity: entity)
            }
            .sheet(isPresented: $startingTimer) {
                StartTimerSheet(childID: selectedChildID)
            }
            .sheet(item: $convertRequest) { request in
                EntityEditorView(kind: request.kind,
                                 childID: request.timer.childID ?? selectedChildID,
                                 sourceTimer: request.timer)
            }
            .sheet(item: $stoppingTimer, onDismiss: {
                // Open the detail editor only after the Stop sheet is fully gone.
                if let pendingConvert { convertRequest = pendingConvert; self.pendingConvert = nil }
            }) { timer in
                StopTimerSheet(timer: timer,
                               onLog: { kind in stopTimer(timer, as: kind) },
                               onDiscard: { discardTimer(timer); stoppingTimer = nil })
            }
            .refreshable { await sync.sync() }
            .onChange(of: router.openTimerLocalID) { _, id in openTimerActions(id) }
            .onChange(of: router.convertTarget) { _, target in openConvert(target) }
            .onAppear {
                // handle a deep link that arrived before this view existed
                openTimerActions(router.openTimerLocalID)
                openConvert(router.convertTarget)
                #if DEBUG
                if let raw = ProcessInfo.processInfo.environment["BB_OPEN"], !children.isEmpty {
                    if raw == "timer", !startingTimer {
                        startingTimer = true
                    } else if let kind = EntityKind(rawValue: raw), addKind == nil {
                        addKind = kind
                    }
                }
                #endif
            }
            .overlay {
                if children.isEmpty { ContentUnavailableView(
                    "No Children", systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Add a child in Baby Buddy to get started.")) }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now, format: .dateTime.weekday(.wide).month().day())
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(currentChildName).font(.title.weight(.semibold))
            }
            Spacer()
            avatar
        }
    }

    private var avatar: some View {
        let circle = Circle()
            .fill(BBColor.brand)
            .frame(width: 42, height: 42)
            .overlay(Text(currentChildName.prefix(1)).font(.headline).foregroundStyle(.white))
        return Group {
            if children.count > 1 {
                Menu {
                    ForEach(children, id: \.serverID) { child in
                        Button {
                            if let id = child.serverID { selectedChildID = id }
                        } label: {
                            Label(childName(child), systemImage: child.serverID == selectedChildID
                                  ? "checkmark" : "person.crop.circle")
                        }
                    }
                } label: { circle }
            } else {
                circle
            }
        }
    }

    // MARK: Active timer

    private func timerHero(_ timer: LocalEntity) -> some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    RunningDot()
                    Text(timerTitle(timer))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BBColor.success)
                    Spacer()
                }
                Text(timer.timestamp, style: .timer)
                    .font(BBFont.timer)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("Started \(timer.timestamp.formatted(date: .omitted, time: .shortened))")
                    .font(.footnote).foregroundStyle(.secondary)
                Button { stoppingTimer = timer } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bbStop)
            }
        }
    }

    private var startTimerCard: some View {
        Button { startingTimer = true } label: {
            BBCard {
                HStack(spacing: 12) {
                    ActivityTile(kind: .timer, size: 40, glyph: 21)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Start a timer").font(.headline)
                        Text("Feeding, sleep, tummy time…")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(children.isEmpty)
    }

    /// Title shown above the running timer. Uses the timer's name when set.
    private func timerTitle(_ timer: LocalEntity) -> String {
        if let name = timer.payloadObject["name"] as? String, !name.isEmpty {
            return "\(name) running"
        }
        return "Timer running"
    }

    // MARK: Today

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader("Today")
            LazyVGrid(columns: columns, spacing: 9) {
                metricLink(.feeding) {
                    MetricTile(kind: .feeding, label: "Feedings", value: "\(count(of: .feeding, today: true))")
                }
                metricLink(.sleep) {
                    MetricTile(kind: .sleep, label: "Sleep", value: sleepTodayText)
                }
                metricLink(.change) {
                    MetricTile(kind: .change, label: "Diapers", value: "\(count(of: .change, today: true))")
                }
                metricLink(.tummyTime) {
                    MetricTile(kind: .tummyTime, label: "Tummy time", value: tummyTodayText)
                }
            }
        }
    }

    /// Wrap a "Today" tile so tapping it pushes a single-day, single-kind timeline slice.
    private func metricLink<Content: View>(_ kind: EntityKind,
                                           @ViewBuilder _ tile: () -> Content) -> some View {
        NavigationLink(value: kind) { tile() }
            .buttonStyle(.plain)
    }

    // MARK: Latest

    private var latestSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionHeader("Latest")
            VStack(spacing: 9) {
                ForEach(latestEvents) { entity in
                    Button { editing = entity } label: { EventRow(entity: entity) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    /// Open the Stop sheet for a timer arriving via deep link (Active Timer widget).
    private func openTimerActions(_ id: UUID?) {
        guard let id,
              let timer = allEntities.first(where: { $0.localID == id && $0.kind == .timer })
        else { return }
        stoppingTimer = timer
        router.openTimerLocalID = nil
    }

    /// Open the pre-filled convert editor for a timer arriving via deep link — the widget Stop
    /// button for activities that need extra fields (feeding/pumping).
    private func openConvert(_ target: DeepLinkRouter.ConvertTarget?) {
        guard let target,
              let timer = allEntities.first(where: { $0.localID == target.localID && $0.kind == .timer })
        else { return }
        convertRequest = ConvertRequest(timer: timer, kind: target.kind)
        router.convertTarget = nil
    }

    /// File a stopped timer as the chosen activity. Sleep/tummy time log in one tap; feeding and
    /// pumping need extra fields, so they defer to the pre-filled convert editor (opened once the
    /// Stop sheet has dismissed). The timer's existing type may be overridden by the picker.
    private func stopTimer(_ timer: LocalEntity, as kind: EntityKind) {
        guard TimerActivity(convertKind: kind)?.isInstantLoggable == true else {
            pendingConvert = ConvertRequest(timer: timer, kind: kind)
            stoppingTimer = nil
            return
        }
        let p = timer.payloadObject
        let start = (p["start"] as? String) ?? APIDate.isoDateTime.string(from: timer.timestamp)
        var payload: [String: Any] = [
            "start": start,
            "end": APIDate.isoDateTime.string(from: .now),
        ]
        if let child = timer.childID { payload["child"] = child }
        LocalRepository(context: context).convertTimer(timer, to: kind, payload: payload)
        let activity = TimerActivity(convertKind: kind)?.rawValue ?? "other"
        Analytics.timerStopped(activity: activity, source: .app)
        Task { await sync.sync() }
        stoppingTimer = nil
    }

    /// Discard a running timer without logging anything.
    private func discardTimer(_ timer: LocalEntity) {
        LocalRepository(context: context).delete(timer)
        Task { await sync.sync() }
    }

    // MARK: Derived data

    private var children: [LocalEntity] { allEntities.filter { $0.kind == .child } }

    private var childEntities: [LocalEntity] {
        allEntities.filter { $0.childID == selectedChildID && $0.syncState != .pendingDelete }
    }

    private var currentChild: LocalEntity? { children.first { $0.serverID == selectedChildID } }

    private var currentChildName: String {
        currentChild.map { childName($0, firstOnly: true) } ?? "Baby Buddy"
    }

    private func childName(_ entity: LocalEntity, firstOnly: Bool = false) -> String {
        let p = entity.payloadObject
        let first = p["first_name"] as? String ?? ""
        let last = p["last_name"] as? String ?? ""
        if firstOnly { return first.isEmpty ? (last.isEmpty ? "Child" : last) : first }
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Child" : name
    }

    private func lastEvent(of kind: EntityKind) -> LocalEntity? {
        childEntities.first { $0.kind == kind }
    }

    private var latestEvents: [LocalEntity] {
        recentKinds.compactMap { lastEvent(of: $0) }.sorted { $0.timestamp > $1.timestamp }
    }

    private var activeTimers: [LocalEntity] {
        childEntities.filter { $0.kind == .timer }
    }

    private func count(of kind: EntityKind, today: Bool) -> Int {
        childEntities.filter {
            $0.kind == kind && (!today || Calendar.current.isDateInToday($0.timestamp))
        }.count
    }

    private var sleepTodayText: String { durationToday(of: .sleep) }
    private var tummyTodayText: String { durationToday(of: .tummyTime) }

    /// Total logged duration today for a start/end-based kind, formatted (or "—").
    private func durationToday(of kind: EntityKind) -> String {
        let total = childEntities
            .filter { $0.kind == kind && Calendar.current.isDateInToday($0.timestamp) }
            .reduce(0.0) { acc, e in
                let p = e.payloadObject
                if let s = p["start"] as? String, let en = p["end"] as? String,
                   let start = APIDate.parse(s), let end = APIDate.parse(en) {
                    return acc + end.timeIntervalSince(start)
                }
                return acc
            }
        return total > 0 ? EntityFormatting.formatInterval(total) : "—"
    }
}

/// Short, pill-friendly label for an activity kind (the full `displayName` is too long for the
/// quick-add stack and grid captions).
private func quickAddLabel(_ kind: EntityKind) -> String {
    switch kind {
    case .change: return "Diaper"
    case .tummyTime: return "Tummy time"
    case .headCircumference: return "Head"
    default: return kind.displayName
    }
}

// MARK: - Quick-add menu

/// The floating "+" action and its quick-action stack. Tapping the button dims the screen and
/// fans up a column of labeled actions — Start timer (hero) plus the most-logged record types —
/// over a "More…" row that opens the full activity list. The "+" morphs into an "×" while open.
private struct QuickAddMenu: View {
    @Binding var isOpen: Bool
    var onStartTimer: () -> Void
    var onLog: (EntityKind) -> Void
    var onMore: () -> Void

    /// The everyday record types surfaced directly in the stack; the rest live behind "More…".
    private let quickKinds: [EntityKind] = [.feeding, .change, .sleep, .tummyTime]
    private let spring = Animation.spring(response: 0.32, dampingFraction: 0.82)
    private let tileSize: CGFloat = 46
    private var tileShape: RoundedRectangle { RoundedRectangle(cornerRadius: 46 * 0.29, style: .continuous) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if isOpen {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .onTapGesture { close() }
            }
            VStack(alignment: .trailing, spacing: 12) {
                if isOpen {
                    actionRow(label: "Start timer", kind: .timer) { onStartTimer() }
                    ForEach(quickKinds) { kind in
                        actionRow(label: quickAddLabel(kind), kind: kind) { onLog(kind) }
                    }
                    moreRow
                }
                fab
            }
            .padding(.trailing, 20)
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
    }

    private var fab: some View {
        Button {
            withAnimation(spring) { isOpen.toggle() }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(isOpen ? 45 : 0))
                .frame(width: 58, height: 58)
                .background(BBColor.brand, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .accessibilityLabel(isOpen ? "Close" : "Add")
    }

    /// A labeled quick action: a tinted glyph tile beside a pill label. Closes the menu, then
    /// runs `action` so the resulting sheet presents after the dim has dismissed.
    private func actionRow(label: String, kind: EntityKind, action: @escaping () -> Void) -> some View {
        Button {
            close()
            action()
        } label: {
            HStack(spacing: 10) {
                pill(label)
                tile(fill: BBColor.activity(kind)) { kind.icon(23) }
            }
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var moreRow: some View {
        Button {
            close()
            onMore()
        } label: {
            HStack(spacing: 10) {
                pill("More…")
                tile(fill: BBColor.note) {
                    Image(systemName: "ellipsis").font(.system(size: 18, weight: .semibold))
                }
            }
        }
        .buttonStyle(.plain)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    /// A solid, filled glyph tile for the stack: the activity color as an opaque fill with a white
    /// glyph. High contrast for every kind and clearly legible over the dim — the shared
    /// translucent ``ActivityTile`` muddied against the dark backdrop.
    private func tile<Glyph: View>(fill: Color, @ViewBuilder glyph: () -> Glyph) -> some View {
        glyph()
            .foregroundStyle(.white)
            .frame(width: tileSize, height: tileSize)
            .background(fill, in: tileShape)
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(BBColor.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }

    private func close() { withAnimation(spring) { isOpen = false } }
}

// MARK: - All activities sheet

/// The full activity picker reached from the quick-add stack's "More…" row: every loggable
/// record type as a tinted glyph tile, grouped into everyday logs and measurements.
private struct AllActivitiesSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onPick: (EntityKind) -> Void

    private let logKinds: [EntityKind] = [.feeding, .change, .sleep, .tummyTime, .pumping, .note]
    private let measureKinds: [EntityKind] = [.weight, .height, .headCircumference, .temperature, .bmi, .medication]
    private let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    section("Log", logKinds)
                    section("Measure", measureKinds)
                }
                .padding()
            }
            .background(BBColor.surface)
            .navigationTitle("Add Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func section(_ title: String, _ kinds: [EntityKind]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title)
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(kinds) { kind in
                    Button { onPick(kind) } label: {
                        VStack(spacing: 7) {
                            ActivityTile(kind: kind, size: 56, glyph: 27)
                            Text(quickAddLabel(kind))
                                .font(.caption).foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

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
    @State private var startingTimer = false
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

    private let quickAddKinds: [EntityKind] = [.feeding, .change, .sleep, .tummyTime, .pumping, .note]
    private let measureKinds: [EntityKind] = [.weight, .height, .headCircumference, .temperature, .bmi, .medication]
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
            .overlay(alignment: .bottomTrailing) {
                if !children.isEmpty {
                    addButton
                        .padding(.trailing, 20)
                        .padding(.bottom, 16)
                }
            }
            .sheet(item: $addKind) { kind in
                EntityEditorView(kind: kind, childID: selectedChildID)
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

    // MARK: Add button

    /// Floating action button (bottom-trailing) opening the add menu: start a timer or log any
    /// record. Adopts the brand color as the screen's primary create action.
    private var addButton: some View {
        Menu {
            Button { startingTimer = true } label: {
                Label { Text("Start Timer") } icon: { EntityKind.timer.icon() }
            }
            Divider()
            ForEach(quickAddKinds) { kind in
                Button { addKind = kind } label: { Label { Text(kind.displayName) } icon: { kind.icon() } }
            }
            Menu("Measurements") {
                ForEach(measureKinds) { kind in
                    Button { addKind = kind } label: { Label { Text(kind.displayName) } icon: { kind.icon() } }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(BBColor.brand, in: Circle())
                .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
        }
        .accessibilityLabel("Add")
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
                ForEach(latestEvents) { EventRow(entity: $0) }
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

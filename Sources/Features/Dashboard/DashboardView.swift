import SwiftUI
import SwiftData

/// Baby Buddy-style overview: most-recent event of each kind, active timers, and today's
/// running counts for the selected child. Reads entirely from the local cache.
struct DashboardView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(DeepLinkRouter.self) private var router
    @Binding var selectedChildID: Int

    @Query(sort: \LocalEntity.timestamp, order: .reverse) private var allEntities: [LocalEntity]
    @State private var addKind: EntityKind?
    @State private var startingTimer = false
    @State private var actionTimer: LocalEntity?
    @State private var convertRequest: ConvertRequest?

    /// A request to convert a specific timer into a specific activity kind.
    private struct ConvertRequest: Identifiable {
        let timer: LocalEntity
        let kind: EntityKind
        var id: String { "\(timer.localID)-\(kind.rawValue)" }
    }

    /// Activity kinds a running timer can be converted into (the duration-based records).
    private let convertKinds: [EntityKind] = [.feeding, .sleep, .tummyTime, .pumping]

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    private let quickAddKinds: [EntityKind] = [.feeding, .change, .sleep, .tummyTime, .pumping, .note]
    private let measureKinds: [EntityKind] = [.weight, .height, .headCircumference, .temperature, .bmi, .medication]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(recentKinds, id: \.self) { kind in
                        lastEventCard(kind)
                    }
                }
                .padding(.horizontal)

                if !activeTimers.isEmpty {
                    timersCard.padding(.horizontal).padding(.top, 4)
                }
                todayCard.padding(.horizontal).padding(.top, 4)
            }
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ChildSwitcher(children: children, selectedChildID: $selectedChildID)
                ToolbarItem(placement: .topBarTrailing) { addMenu }
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
            .confirmationDialog("Timer", isPresented: timerActionPresented,
                                presenting: actionTimer) { timer in
                ForEach(convertKinds) { kind in
                    Button("Convert to \(kind.displayName)") {
                        convertRequest = ConvertRequest(timer: timer, kind: kind)
                    }
                }
                Button("Discard Timer", role: .destructive) {
                    LocalRepository(context: context).delete(timer)
                    Task { await sync.sync() }
                }
            } message: { timer in
                Text(EntityFormatting.subtitle(timer) ?? "Timer")
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

    // MARK: Toolbar

    private var addMenu: some View {
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
        }
        .disabled(children.isEmpty)
    }

    // MARK: Cards

    private let recentKinds: [EntityKind] = [.feeding, .change, .sleep, .tummyTime]

    @ViewBuilder private func lastEventCard(_ kind: EntityKind) -> some View {
        DashboardCard(title: "Last \(kind.displayName)", icon: { kind.icon(15) }) {
            if let entity = lastEvent(of: kind) {
                Text(entity.timestamp, format: .relative(presentation: .named))
                    .font(.headline)
                if let subtitle = EntityFormatting.subtitle(entity), !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            } else {
                Text("—").font(.headline).foregroundStyle(.secondary)
            }
        }
    }

    private var timersCard: some View {
        DashboardCard(title: "Active Timers", systemImage: "timer") {
            ForEach(activeTimers) { timer in
                Button { actionTimer = timer } label: {
                    HStack {
                        Text(EntityFormatting.subtitle(timer) ?? "Timer")
                        Spacer()
                        Text(timer.timestamp, style: .timer).monospacedDigit()
                        Image(systemName: "chevron.right")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                    .font(.subheadline)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Drives the timer action sheet; clears the selection when dismissed.
    private var timerActionPresented: Binding<Bool> {
        Binding(get: { actionTimer != nil }, set: { if !$0 { actionTimer = nil } })
    }

    /// Open the convert/stop sheet for a timer arriving via deep link (Active Timer widget).
    private func openTimerActions(_ id: UUID?) {
        guard let id,
              let timer = allEntities.first(where: { $0.localID == id && $0.kind == .timer })
        else { return }
        actionTimer = timer
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

    private var todayCard: some View {
        DashboardCard(title: "Today", systemImage: "calendar") {
            HStack(spacing: 20) {
                stat("Feedings", count(of: .feeding, today: true))
                stat("Changes", count(of: .change, today: true))
                stat("Sleep", sleepTodayText)
            }
        }
    }

    private func stat(_ label: String, _ value: Int) -> some View {
        stat(label, "\(value)")
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack {
            Text(value).font(.title2.bold())
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    // MARK: Derived data

    private var children: [LocalEntity] { allEntities.filter { $0.kind == .child } }

    private var childEntities: [LocalEntity] {
        allEntities.filter { $0.childID == selectedChildID && $0.syncState != .pendingDelete }
    }

    private func lastEvent(of kind: EntityKind) -> LocalEntity? {
        childEntities.first { $0.kind == kind }
    }

    private var activeTimers: [LocalEntity] {
        childEntities.filter { $0.kind == .timer }
    }

    private func count(of kind: EntityKind, today: Bool) -> Int {
        childEntities.filter {
            $0.kind == kind && (!today || Calendar.current.isDateInToday($0.timestamp))
        }.count
    }

    private var sleepTodayText: String {
        let total = childEntities
            .filter { $0.kind == .sleep && Calendar.current.isDateInToday($0.timestamp) }
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

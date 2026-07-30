import SwiftUI
import SwiftData
import UIKit

/// Baby Buddy-style overview: active timer hero, today's running totals, and the most-recent
/// event of each kind for the selected child. Reads entirely from the local cache.
struct DashboardView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var context
    @Environment(DeepLinkRouter.self) private var router
    @Environment(LiveActivityManager.self) private var liveActivity
    @Environment(PurchaseManager.self) private var purchases
    @Environment(AppLockManager.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @Binding var selectedChildID: Int

    @Query(sort: \LocalEntity.timestamp, order: .reverse) private var allEntities: [LocalEntity]
    /// Navigation path for the day-timeline pushes (in-app "Today" tiles + the status widget).
    @State private var navPath: [EntityKind] = []
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

    // MARK: Support nudge state
    //
    // The Dashboard is the only place the support nudges appear (see ``SupportNudgeManager``), so it
    // owns their presentation — and the "is anything else happening?" judgement they depend on.

    /// The nudge the Dashboard draws itself: the gentle-ask overlay or the inline banner. The
    /// milestone sheet is tracked separately in `milestoneAsk`, because `.sheet(item:)` owns a
    /// lifecycle (a swipe-down) that an overlay has no equivalent of.
    @State private var inlineNudge: SupportNudge = .none
    @State private var milestoneAsk: MilestoneAsk?
    /// Set when a nudge's blue button is tapped, so closing that surface isn't counted as a refusal
    /// and the supporter sheet takes its place.
    @State private var acceptedNudge = false
    @State private var showingSupporter = false
    /// Which nudge sent the customer to the supporter sheet — the tip's attribution.
    @State private var supporterSource: Analytics.SupporterSource = .nudgeGentle
    /// Bumped to re-ask the policy (on foreground); `.task(id:)` also runs it on first appearance.
    @State private var nudgeCheck = 0
    // Watched so a surface already on screen can be taken back the moment the reminders are switched
    // off; the key comes from ``SupportNudgeStore`` so it can't drift from the one the policy reads.
    @AppStorage(SupportNudgeStore.remindersEnabledKey) private var supportRemindersEnabled = true

    /// A request to convert a specific timer into a specific activity kind.
    private struct ConvertRequest: Identifiable {
        let timer: LocalEntity
        let kind: EntityKind
        var id: String { "\(timer.localID)-\(kind.rawValue)" }
    }

    /// Wraps a milestone count so `.sheet(item:)` has an `Identifiable` to present.
    private struct MilestoneAsk: Identifiable {
        let count: Int
        var id: Int { count }
    }

    private let columns = [GridItem(.flexible(), spacing: 9), GridItem(.flexible(), spacing: 9)]

    private let recentKinds: [EntityKind] = [.feeding, .change, .sleep, .tummyTime, .pumping]

    var body: some View {
        NavigationStack(path: $navPath) {
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

                    if inlineNudge == .banner, !nudgesSilenced {
                        SupportBanner(
                            onSupport: { acceptNudge(.banner) },
                            onDismiss: { dismissNudge(.banner) })
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
            .sheet(item: $milestoneAsk, onDismiss: finishMilestoneAsk) { ask in
                SupportMilestoneSheet(
                    count: ask.count,
                    onSupport: { acceptedNudge = true; milestoneAsk = nil },
                    onDismiss: { milestoneAsk = nil })
            }
            .sheet(isPresented: $showingSupporter) { SupporterSheet(source: supporterSource) }
            .refreshable { await sync.sync() }
            .onChange(of: router.openTimerLocalID) { _, id in openTimerActions(id) }
            .onChange(of: router.convertTarget) { _, target in openConvert(target) }
            .onChange(of: router.openDayKind) { _, kind in openDay(kind) }
            .onAppear {
                // handle a deep link that arrived before this view existed
                openTimerActions(router.openTimerLocalID)
                openConvert(router.convertTarget)
                openDay(router.openDayKind)
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
            // Above the quick-add stack and the empty state: while the gentle ask is up it is the
            // only thing on screen that should be reachable.
            .overlay {
                if inlineNudge == .gentleAsk, !nudgesSilenced {
                    SupportGentleAskCard(
                        onSupport: { acceptNudge(.gentle) },
                        onDismiss: { dismissNudge(.gentle) })
                }
            }
            .task(id: nudgeCheck) { await considerNudge() }
            .onChange(of: scenePhase) { _, phase in
                // A returning customer gets the ask, rather than only ever a cold launch.
                if phase == .active { nudgeCheck += 1 }
            }
            .onChange(of: nudgesSilenced) { _, silenced in
                if silenced { withdrawNudges() }
            }
        }
    }

    // MARK: Support nudge

    /// Whether the ask has been settled since the surface went up — by tipping from another entry
    /// point, or by switching the reminders off.
    ///
    /// The policy is consulted once, at the moment a nudge is due; this is the live half of the same
    /// two rules, because the customer can reach Settings (the tab bar stays live, and the banner
    /// never blocked anything) while a nudge is on screen. Without it, a banner keeps asking someone
    /// who has just paid — and `isBusy` would hold it there for the rest of the session.
    private var nudgesSilenced: Bool {
        purchases.isSupporter || !supportRemindersEnabled
    }

    /// Take back whatever is on screen. Not a dismissal: nobody refused this ask, it stopped being
    /// the right thing to show — so the retirement tally and the snooze are both left alone.
    private func withdrawNudges() {
        withAnimation(.snappy(duration: 0.2)) { inlineNudge = .none }
        milestoneAsk = nil
    }

    /// Whether something else has the screen. Every sheet, the editor, the quick-add stack, both
    /// halves of the timer-stop flow, the app lock, and the no-children empty state all count: a
    /// nudge landing on a tired parent mid-log is the exact thing this policy exists to avoid.
    private var isBusy: Bool {
        addKind != nil || editing != nil || startingTimer || quickAddOpen || showAllActivities
            || pendingAddKind != nil || stoppingTimer != nil || convertRequest != nil
            || pendingConvert != nil || showingSupporter || router.showSupporter
            || inlineNudge != .none || milestoneAsk != nil
            || lock.isLocked || children.isEmpty
    }

    /// Ask the policy whether a support surface is due — a beat after the Dashboard settles.
    ///
    /// The delay earns its keep twice: a modal that arrives with the first frame reads as an ambush,
    /// and it gives a deep link or a restored sheet time to claim the screen first. So the guards are
    /// re-checked on the far side of it.
    ///
    /// Including the foreground check, which is not redundant: backgrounding doesn't disappear this
    /// view, so `.task` isn't cancelled and the continuation would otherwise fire during iOS's
    /// post-background wind-down. `present` would then stamp `lastNudge` — permanently consuming the
    /// once-ever gentle ask, or retiring a milestone — for a surface nobody ever saw. The state must
    /// be read live rather than from the captured `scenePhase`, which is snapshotted per body pass
    /// and is stale by the time the sleep returns.
    private func considerNudge() async {
        guard !isBusy else { return }
        try? await Task.sleep(for: .seconds(1.2))
        guard !Task.isCancelled, !isBusy,
              UIApplication.shared.applicationState == .active
        else { return }
        present(SupportNudgeStore.shared.pending(isSupporter: purchases.isSupporter))
    }

    /// Put a due nudge on screen and record that it was shown (which restarts the 21-day cap).
    private func present(_ nudge: SupportNudge) {
        guard nudge != .none else { return }
        SupportNudgeStore.shared.markShown(nudge)
        acceptedNudge = false
        if let count = nudge.milestoneCount {
            milestoneAsk = MilestoneAsk(count: count)
        } else {
            withAnimation(.snappy(duration: 0.25)) { inlineNudge = nudge }
        }
    }

    /// The blue button on the gentle ask or the banner: close the surface, then open the app's one
    /// purchase sheet, credited to the variant that sent them there.
    private func acceptNudge(_ variant: Analytics.NudgeVariant) {
        withAnimation(.snappy(duration: 0.2)) { inlineNudge = .none }
        openSupporter(from: variant == .banner ? .nudgeBanner : .nudgeGentle)
    }

    /// The quiet button, the scrim, or the banner's "×": one tap, counted against the retirement
    /// tally, and snoozed for at least three weeks.
    private func dismissNudge(_ variant: Analytics.NudgeVariant) {
        SupportNudgeStore.shared.markDismissed(variant)
        withAnimation(.snappy(duration: 0.2)) { inlineNudge = .none }
    }

    /// The milestone sheet has finished dismissing. A swipe-down is a "no" every bit as much as
    /// "Not now" is; only the blue button isn't — and the supporter sheet can only be presented now
    /// that this one is fully gone.
    private func finishMilestoneAsk() {
        let accepted = acceptedNudge
        acceptedNudge = false
        if accepted {
            openSupporter(from: .nudgeMilestone)
        } else if !nudgesSilenced {
            // Withdrawn by ``withdrawNudges()`` rather than turned down — a tip from Settings or the
            // reminders switch isn't a refusal, so it must not count toward retirement.
            SupportNudgeStore.shared.markDismissed(.milestone)
        }
    }

    /// Open the supporter sheet. The source is the whole conversion signal: a tip that follows
    /// carries it, so there is no separate "converted" event to join against.
    private func openSupporter(from source: Analytics.SupporterSource) {
        supporterSource = source
        showingSupporter = true
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
        let photo = ChildAvatar(
            pictureURL: currentChild?.payloadObject["picture"] as? String,
            initial: String(currentChildName.prefix(1)),
            size: 42)
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
                } label: { photo }
                .accessibilityLabel("Current child, \(currentChildName)")
                .accessibilityHint("Switch child")
            } else {
                photo // decorative — the child's name is shown in the header beside it
            }
        }
    }

    // MARK: Active timer

    private func timerHero(_ timer: LocalEntity) -> some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        RunningDot().accessibilityHidden(true)
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
                }
                // Read the running timer as one phrase; the live seconds aren't announced (they'd
                // fire VoiceOver every second), but the label and start time are.
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(timerTitle(timer)), started \(timer.timestamp.formatted(date: .omitted, time: .shortened))")
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

    /// Push a kind's day timeline for a status-widget tile tap (same destination as the in-app
    /// "Today" tiles).
    private func openDay(_ kind: EntityKind?) {
        guard let kind else { return }
        navPath = [kind]
        router.openDayKind = nil
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
        Task { await liveActivity.reconcile() } // end the Live Activity for the stopped timer
        stoppingTimer = nil
    }

    /// Discard a running timer without logging anything.
    private func discardTimer(_ timer: LocalEntity) {
        LocalRepository(context: context).delete(timer)
        Task { await sync.sync() }
        Task { await liveActivity.reconcile() } // end the Live Activity for the discarded timer
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
        FloatingAddButton(rotated: isOpen,
                          accessibilityLabelText: isOpen ? "Close" : "Add") {
            withAnimation(spring) { isOpen.toggle() }
        }
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

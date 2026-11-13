import SwiftUI
import SwiftData

/// Files a stopped timer: shows what's being logged (activity + the duration frozen at Stop) and
/// lets you confirm or change the type. The timer stopped when Stop was tapped, so closing the
/// sheet leaves it stopped; "Resume timer" undoes that. Logging, resuming and discarding are handed
/// back to the caller (the dashboard owns the cache writes + sync); for feeding/pumping the caller
/// routes to the pre-filled detail editor, which needs extra fields.
/// The Started time is a picker, and "Restart from now" resumes from zero, for a timer started
/// late or by mistake (#72).
struct StopTimerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @Environment(\.dynamicTypeSize) private var typeSize

    let timer: LocalEntity
    let onLog: (EntityKind) -> Void
    let onResume: () -> Void
    let onDiscard: () -> Void

    @State private var selected: EntityKind?
    @State private var wide = false
    @State private var detent: PresentationDetent = .medium
    /// The middle of the first tile and the top of the buttons pinned below the tiles, in global
    /// coordinates, for ``openTallEnough()``. Zero until measured.
    @State private var firstTileMid: CGFloat = 0
    @State private var actionsTop: CGFloat = 0
    @State private var checkedHeight = false

    /// The convertible activities — same set as the Start Timer grid.
    private let activities: [EntityKind] = [.feeding, .sleep, .tummyTime, .pumping]
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(timer: LocalEntity, onLog: @escaping (EntityKind) -> Void, onResume: @escaping () -> Void,
         onDiscard: @escaping () -> Void) {
        self.timer = timer
        self.onLog = onLog
        self.onResume = onResume
        self.onDiscard = onDiscard
        _selected = State(initialValue: TimerActivity(timer: timer)?.convertKind)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                // On iPhone Duo's open display: what happened left, what to do with it right.
                SheetColumns(wide: wide) {
                    summaryCard
                    SectionHeader(String(localized: "Log as"))
                    // Keep all four choices in the accessibility tree while the form scrolls.
                    if typeSize.isAccessibilitySize {
                        VStack(spacing: 12) { activityTiles }
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) { activityTiles }
                    }
                } trailing: {
                    if wide || typeSize.isAccessibilitySize { actions }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, typeSize.isAccessibilitySize ? 16 : 0)
            }
            .trackingWide($wide)
            // The open display: the tiles fill the left column, and half height cuts them off.
            .onChange(of: wide) { if wide { detent = .large } }
            .task(id: actionsTop) { await openTallEnough() }
            .background(BBColor.surface)
            .navigationTitle("Stop Timer")
            .accessibilityIdentifier("screen-stop-timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) {
                if !wide && !typeSize.isAccessibilitySize {
                    actions
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .background(BBColor.surface)
                        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { actionsTop = $0 }
                }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large], selection: $detent)
        .onChange(of: typeSize, initial: true) {
            if typeSize.isAccessibilitySize { detent = .large }
        }
    }

    /// Opens the sheet full height when less than half of the first row of "Log as" tiles shows at
    /// half height, as on iPhone Duo's front display, which is short for its width. A phone shows
    /// the first row whole and keeps half height. The sheet grows through several sizes as it
    /// presents, so this waits for its height to hold still, then decides once, which leaves the
    /// sheet free to be dragged back down.
    private func openTallEnough() async {
        guard !checkedHeight, actionsTop > 0 else { return }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled, !checkedHeight else { return }
        checkedHeight = true
        if detent == .medium, firstTileMid > actionsTop { detent = .large }
    }

    private var activityTiles: some View {
        ForEach(activities) { kind in
            ActivityPickTile(kind: kind, isSelected: selected == kind) {
                selected = (selected == kind) ? nil : kind
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).midY } action: {
                guard kind == activities.first else { return }
                firstTileMid = $0
            }
        }
    }

    // MARK: Summary

    /// One row on a phone. A narrower card, in the left column of the open display's wide sheet,
    /// moves the count under the name, and a narrower one still stacks everything. The name stays
    /// on one line in the first two: the row squeezed it onto two rather than give way to the next.
    private var summaryCard: some View {
        BBCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    summaryTile
                    VStack(alignment: .leading, spacing: 3) {
                        summaryHeadline.fixedSize()
                        startedRow
                    }
                    Spacer(minLength: 8)
                    duration
                }
                HStack(alignment: .top, spacing: 14) {
                    summaryTile
                    VStack(alignment: .leading, spacing: 6) {
                        summaryHeadline.fixedSize()
                        startedRow
                        duration
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    summaryTile
                    summaryHeadline
                    startedRow
                    duration
                }
            }
        }
    }

    private var summaryTile: some View { ActivityTile(kind: selected ?? .timer, size: 46, glyph: 24) }

    /// Identified because the "Log as" tile beside it can carry the same name.
    private var summaryHeadline: some View {
        Text(headline).font(.headline).accessibilityIdentifier("stop-timer-activity")
    }

    private var startedRow: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 6))
        return layout {
            Text("Started").font(.caption).foregroundStyle(.secondary).fixedSize()
            DatePicker("Started", selection: Binding(get: { timer.timestamp }, set: setStartTime),
                       displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(BBColor.brandAccent)
        }
    }

    private var duration: some View {
        Text(EntityFormatting.clock(elapsed))
            .font(.title2.weight(.semibold)).monospacedDigit()
            .accessibilityLabel("Stopped after \(EntityFormatting.spokenDuration(elapsed))")
    }

    /// Frozen at Stop, so a parent who walks away mid-sheet comes back to the same number.
    private var elapsed: TimeInterval { (timer.stoppedAt ?? .now).timeIntervalSince(timer.timestamp) }

    /// The picker is time only, to fit beside the count, so a picked time means its last occurrence:
    /// 11:50 PM for a timer started at 12:10 AM is yesterday's.
    private func setStartTime(_ picked: Date) {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: picked)
        setStart(calendar.nextDate(after: .now, matching: time, matchingPolicy: .nextTime,
                                   direction: .backward) ?? picked)
    }

    /// The timer is stopped, so this only moves the frozen count; the repository decides what
    /// reaches the server (nothing until the timer is logged or resumed).
    private func setStart(_ date: Date) {
        LocalRepository(context: context).setTimerStart(timer, to: date)
    }

    /// Reflects what's being logged: the chosen type (so it stays in step with the tile and the
    /// picker), falling back to the timer's name when no type is selected.
    private var headline: String {
        if let selected { return selected.displayName }
        if let name = timer.payloadObject["name"] as? String, !name.isEmpty { return name }
        return String(localized: "Timer")
    }

    // MARK: Actions

    /// Log, then the quieter choices: in a row under it on a phone, and one above the other in the
    /// right column of a wide sheet, with Discard last.
    private var actions: some View {
        VStack(spacing: wide ? 14 : 8) {
            Button { if let selected { onLog(selected) } } label: { Text(logTitle) }
                .buttonStyle(logStyle)
                .disabled(selected == nil)
                .opacity(selected == nil ? 0.5 : 1)

            Group {
                if wide || typeSize.isAccessibilitySize {
                    VStack(spacing: 14) { secondaryActions }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            Button("Resume timer") { onResume() }
                                .foregroundStyle(BBColor.brandAccent)
                            Spacer(minLength: 12)
                            Button("Restart from now") { setStart(.now); onResume() }
                                .foregroundStyle(BBColor.brandAccent)
                            Spacer(minLength: 12)
                            Button("Discard timer", role: .destructive) { onDiscard() }
                                .foregroundStyle(BBColor.danger)
                        }
                        VStack(spacing: 14) { secondaryActions }
                    }
                }
            }
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder private var secondaryActions: some View {
        Button("Resume timer") { onResume() }
            .foregroundStyle(BBColor.brandAccent)
        Button("Restart from now") { setStart(.now); onResume() }
            .foregroundStyle(BBColor.brandAccent)
        Button("Discard timer", role: .destructive) { onDiscard() }
            .foregroundStyle(BBColor.danger)
    }

    private var logTitle: String {
        guard let selected else { return String(localized: "Choose a type to log") }
        // Feeding/pumping need type/method/amount, so logging them continues to a detail form.
        let needsDetails = TimerActivity(convertKind: selected)?.isInstantLoggable == false
        return String(localized: "Log \(selected.sentenceName)\(needsDetails ? "…" : "")")
    }

    /// The log button adopts the chosen activity's color (dark-on-tint label for both modes);
    /// brand-blue while nothing is chosen.
    private var logStyle: BBFilledButton {
        guard let selected else { return .bbPrimary }
        return BBFilledButton(background: BBColor.activity(selected),
                              foreground: Color.adaptive(light: "FFFFFF", dark: "0C0E12"))
    }
}

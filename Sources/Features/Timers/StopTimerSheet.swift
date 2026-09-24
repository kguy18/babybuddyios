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

    let timer: LocalEntity
    let onLog: (EntityKind) -> Void
    let onResume: () -> Void
    let onDiscard: () -> Void

    @State private var selected: EntityKind?

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
                VStack(alignment: .leading, spacing: 18) {
                    summaryCard
                    SectionHeader("Log as")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(activities) { kind in
                            ActivityPickTile(kind: kind, isSelected: selected == kind) {
                                selected = (selected == kind) ? nil : kind
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(BBColor.surface)
            .navigationTitle("Stop Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { actions }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: Summary

    private var summaryCard: some View {
        BBCard {
            HStack(spacing: 14) {
                ActivityTile(kind: selected ?? .timer, size: 46, glyph: 24)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline).font(.headline)
                    HStack(spacing: 6) {
                        Text("Started").font(.caption).foregroundStyle(.secondary)
                        DatePicker("Started", selection: Binding(get: { timer.timestamp }, set: setStartTime),
                                   displayedComponents: .hourAndMinute)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(BBColor.brandAccent)
                    }
                }
                Spacer(minLength: 8)
                Text(EntityFormatting.clock(elapsed))
                    .font(.title2.weight(.semibold)).monospacedDigit()
                    .accessibilityLabel("Stopped after \(EntityFormatting.spokenDuration(elapsed))")
            }
        }
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
        return "Timer"
    }

    // MARK: Actions

    private var actions: some View {
        VStack(spacing: 8) {
            Button { if let selected { onLog(selected) } } label: { Text(logTitle) }
                .buttonStyle(logStyle)
                .disabled(selected == nil)
                .opacity(selected == nil ? 0.5 : 1)

            HStack {
                Button("Resume timer") { onResume() }
                    .foregroundStyle(BBColor.brandAccent)
                Spacer()
                // Started by mistake: it runs on from now instead of the original start.
                Button("Restart from now") { setStart(.now); onResume() }
                    .foregroundStyle(BBColor.brandAccent)
                Spacer()
                Button("Discard timer", role: .destructive) { onDiscard() }
                    .foregroundStyle(BBColor.danger)
            }
            .font(.subheadline.weight(.medium))
            .lineLimit(1).minimumScaleFactor(0.8)
            .padding(.vertical, 4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(BBColor.surface)
    }

    private var logTitle: String {
        guard let selected else { return "Choose a type to log" }
        // Feeding/pumping need type/method/amount, so logging them continues to a detail form.
        let needsDetails = TimerActivity(convertKind: selected)?.isInstantLoggable == false
        return "Log \(selected.displayName.lowercased())\(needsDetails ? "…" : "")"
    }

    /// The log button adopts the chosen activity's color (dark-on-tint label for both modes);
    /// brand-blue while nothing is chosen.
    private var logStyle: BBFilledButton {
        guard let selected else { return .bbPrimary }
        return BBFilledButton(background: BBColor.activity(selected),
                              foreground: Color.adaptive(light: "FFFFFF", dark: "0C0E12"))
    }
}

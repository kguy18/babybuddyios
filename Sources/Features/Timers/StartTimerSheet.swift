import SwiftUI
import SwiftData

/// Starts a new Baby Buddy timer (open-ended: no end). It starts now unless back-dated with the
/// "−5 / −15 / −30 min" chips or the start picker, for the nap noticed late. Pick an activity from the
/// grid and the timer remembers it, so stopping it later files straight to that record with no
/// "convert to…?" step; or start an uncategorized timer with the quiet escape hatch. Created
/// through ``LocalRepository`` like any record, so it works offline and syncs when reconnected.
struct StartTimerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Environment(LiveActivityManager.self) private var liveActivity
    @Environment(\.dismiss) private var dismiss

    let childID: Int
    @State private var name = ""
    @State private var selected: EntityKind?
    /// Minutes before the Start tap (0 = now); `nil` once a start is picked, which `customStart` holds.
    @State private var minutesBack: Int? = 0
    @State private var customStart = Date.now

    /// The convertible activities a timer can become — same set as the dashboard's convert menu.
    private let activities: [EntityKind] = [.feeding, .sleep, .tummyTime, .pumping]

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    SectionHeader("Activity")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(activities) { kind in
                            ActivityPickTile(kind: kind, isSelected: selected == kind) {
                                selected = (selected == kind) ? nil : kind
                            }
                        }
                    }
                    detailsCard
                    Text("The timer counts up from its start until you stop it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
            .background(BBColor.surface)
            .navigationTitle("Start Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .safeAreaInset(edge: .bottom) { startBar }
        }
    }

    // MARK: Details

    private var detailsCard: some View {
        BBCard(cornerRadius: BBRadius.card, padding: 0) {
            VStack(spacing: 0) {
                HStack {
                    Text("Name").font(.subheadline).foregroundStyle(.secondary)
                    TextField("Optional", text: $name)
                        .multilineTextAlignment(.trailing)
                        .submitLabel(.done)
                }
                .padding(.horizontal, 15).padding(.vertical, 13)

                Rectangle().fill(BBColor.divider).frame(height: 1).padding(.leading, 15)

                VStack(spacing: 10) {
                    HStack {
                        Text("Starts").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        DatePicker("Starts", selection: Binding(
                            get: { startDate() },
                            set: { customStart = min($0, .now); minutesBack = nil }
                        ), in: ...Date.now, displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .tint(BBColor.brandAccent)
                    }
                    BBSegmentedControl(selection: $minutesBack, options: [0, 5, 15, 30]) { minutes in
                        minutes == 0 ? "Now" : "−\(minutes ?? 0) min"
                    }
                }
                .padding(.horizontal, 15).padding(.vertical, 11)
            }
        }
    }

    // MARK: Start actions

    private var startBar: some View {
        VStack(spacing: 6) {
            Button { start(kind: selected) } label: { Text(startTitle) }
                .buttonStyle(startStyle)

            // Lower-emphasis escape hatch: once an activity is picked, still allow an
            // uncategorized timer (with none picked, the primary button already does this).
            if selected != nil {
                Button("Start without a type") { start(kind: nil) }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(BBColor.surface)
    }

    private var startTitle: String {
        if let selected { return "Start \(selected.displayName.lowercased()) timer" }
        return "Start timer"
    }

    /// The primary button adopts the chosen activity's color (dark-on-tint label for contrast in
    /// both modes); with nothing picked it falls back to the brand-blue primary.
    private var startStyle: BBFilledButton {
        guard let selected else { return .bbPrimary }
        return BBFilledButton(background: BBColor.activity(selected),
                              foreground: Color.adaptive(light: "FFFFFF", dark: "0C0E12"))
    }

    private func startDate(now: Date = .now) -> Date {
        minutesBack.map { now.addingTimeInterval(-Double($0) * 60) } ?? customStart
    }

    private func start(kind: EntityKind?) {
        var payload: [String: Any] = [
            "child": childID,
            "start": APIDate.isoDateTime.string(from: startDate()),
        ]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            payload["name"] = trimmed
        } else if let kind, let activity = TimerActivity(convertKind: kind) {
            // Default the display name to the activity so the running timer reads "Sleep", etc.
            payload["name"] = activity.timerName
        }
        LocalRepository(context: context).create(kind: .timer, payload: payload, timerActivity: kind)
        let activity = kind.flatMap { TimerActivity(convertKind: $0) }?.rawValue ?? "other"
        Analytics.timerStarted(activity: activity, source: .app)
        Task { await sync.sync() }
        Task { await liveActivity.reconcile() } // start the Live Activity for the new timer
        dismiss()
    }
}

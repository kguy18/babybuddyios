import SwiftUI
import SwiftData

/// Starts a new Baby Buddy timer (open-ended: start = now, no end). Pick an activity from the
/// grid and the timer remembers it, so stopping it later files straight to that record with no
/// "convert to…?" step; or start an uncategorized timer with the quiet escape hatch. Created
/// through ``LocalRepository`` like any record, so it works offline and syncs when reconnected.
struct StartTimerSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss

    let childID: Int
    @State private var name = ""
    @State private var selected: EntityKind?

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
                    Text("The timer starts now and counts up until you stop it.")
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

                HStack {
                    Text("Starts").font(.subheadline).foregroundStyle(.secondary)
                    Spacer()
                    Text(Date.now.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.medium)).monospacedDigit()
                }
                .padding(.horizontal, 15).padding(.vertical, 13)
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

    private func start(kind: EntityKind?) {
        var payload: [String: Any] = [
            "child": childID,
            "start": APIDate.isoDateTime.string(from: .now),
        ]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            payload["name"] = trimmed
        } else if let kind, let activity = TimerActivity(convertKind: kind) {
            // Default the display name to the activity so the running timer reads "Sleep", etc.
            payload["name"] = activity.timerName
        }
        LocalRepository(context: context).create(kind: .timer, payload: payload, timerActivity: kind)
        Task { await sync.sync() }
        dismiss()
    }
}

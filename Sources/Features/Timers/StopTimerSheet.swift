import SwiftUI

/// Confirms stopping a running timer: shows what's being logged (activity + elapsed) and lets you
/// confirm or change the type before it's filed, replacing the system action-sheet popup. Logging
/// and discarding are handed back to the caller (the dashboard owns the cache writes + sync); for
/// feeding/pumping the caller routes to the pre-filled detail editor, which needs extra fields.
struct StopTimerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let timer: LocalEntity
    let onLog: (EntityKind) -> Void
    let onDiscard: () -> Void

    @State private var selected: EntityKind?

    /// The convertible activities — same set as the Start Timer grid.
    private let activities: [EntityKind] = [.feeding, .sleep, .tummyTime, .pumping]
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    init(timer: LocalEntity, onLog: @escaping (EntityKind) -> Void, onDiscard: @escaping () -> Void) {
        self.timer = timer
        self.onLog = onLog
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
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
                    Text("Started \(timer.timestamp.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(timer.timestamp, style: .timer)
                    .font(.title2.weight(.semibold)).monospacedDigit()
            }
        }
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

            Button("Discard timer", role: .destructive) { onDiscard() }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BBColor.danger)
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

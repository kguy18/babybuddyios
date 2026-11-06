import SwiftUI

/// Settings ▸ Notifications ▸ Forgotten timer alerts: the switch, and the per-activity thresholds
/// beneath it once it's on. Its own screen because five threshold rows unfolding in the middle of
/// Settings pushed everything below them off the page.
struct TimerAlertsView: View {
    @AppStorage(ForgottenTimerPolicy.enabledKey, store: SharedDefaults.suite) private var enabled = false
    /// The thresholds live in the App Group, which SwiftUI can't observe through
    /// `ForgottenTimerPolicy.threshold(for:)` — a pick never redrew the row. This mirror is what
    /// the rows read; `threshold(_:)` writes both. Reloaded on appear: the initial value is
    /// captured when Settings builds this destination, so a second visit showed the picks from
    /// before the first.
    @State private var thresholds: [TimerActivity: TimeInterval] = stored()

    private static func stored() -> [TimerActivity: TimeInterval] {
        Dictionary(uniqueKeysWithValues: TimerActivity.allCases.map { ($0, ForgottenTimerPolicy.threshold(for: $0)) })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    BBCard(cornerRadius: BBRadius.tile, padding: 0) {
                        SettingsRow(symbol: "bell.badge", tint: BBColor.restart, title: String(localized: "Forgotten timer alerts")) {
                            SettingsView.alertToggle(String(localized: "Forgotten timer alerts"), $enabled, setting: "forgottenTimerAlerts")
                        }
                        .padding(.horizontal, 15)
                    }
                    Text("Get a notification when a timer runs longer than expected, so a forgotten one doesn't file a bogus record. Tap it to open Stop Timer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 2)
                }

                if enabled {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(String(localized: "Alert after"))
                        BBCard(cornerRadius: BBRadius.tile, padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(TimerActivity.allCases.enumerated()), id: \.element) { index, activity in
                                    if index > 0 {
                                        Rectangle().fill(BBColor.divider).frame(height: 0.5)
                                    }
                                    SettingsRow(symbol: activity.systemImage, tint: BBColor.tint(for: activity),
                                                title: activity.timerName) {
                                        Menu {
                                            Picker(activity.timerName, selection: threshold(activity)) {
                                                ForEach(ForgottenTimerPolicy.choices(for: activity), id: \.self) {
                                                    Text(EntityFormatting.formatInterval($0)).tag($0)
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text(EntityFormatting.formatInterval(thresholds[activity] ?? ForgottenTimerPolicy.threshold(for: activity)))
                                                    .font(.subheadline.weight(.medium))
                                                    .foregroundStyle(BBColor.brandAccent)
                                                Image(systemName: "chevron.up.chevron.down")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(BBColor.brandAccent)
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 15)
                        }
                        Text("A timer nags once. The alert stays until the timer stops.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .animation(.default, value: enabled)
        }
        .background(BBColor.surface)
        .onAppear { thresholds = Self.stored() }
        .navigationTitle("Forgotten timer alerts")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func threshold(_ activity: TimerActivity) -> Binding<TimeInterval> {
        Binding(
            get: { thresholds[activity] ?? ForgottenTimerPolicy.threshold(for: activity) },
            set: { seconds in
                thresholds[activity] = seconds
                SharedDefaults.suite.set(seconds, forKey: ForgottenTimerPolicy.thresholdKey(activity))
                Task { await LocalAlerts.shared.reconcile() }
            })
    }
}

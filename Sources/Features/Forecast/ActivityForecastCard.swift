import SwiftUI

struct ActivityForecastCard: View {
    let entities: [LocalEntity]
    let childID: Int
    let lastSync: Date?
    @AppStorage(ForecastPreferences.enabledKey, store: SharedDefaults.suite) private var enabled = false

    var body: some View {
        if enabled {
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                // A save can arrive between ticks. Its end time must not appear to be in the
                // future merely because TimelineView's last scheduled date is a minute old.
                let now = max(timeline.date, Date.now)
                let snapshot = ForecastCache.snapshot(entities, childID: childID, lastSync: lastSync, now: now)
                ForecastSummaryView(snapshot: snapshot)
            }
        }
    }
}

struct ForecastSummaryView: View {
    let snapshot: ForecastSnapshot

    var body: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(forecastText("What's next"), systemImage: "clock.arrow.circlepath").font(.headline)
                    Spacer()
                    Text(forecastText("Calculated")).font(.caption).foregroundStyle(.secondary)
                }
                ForEach(snapshot.cues) { cue in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(cue.kind.title).font(.subheadline.weight(.semibold))
                        if cue.state == .ready, let estimate = cue.estimate {
                            Text(ForecastFormat.window(estimate.window)).font(.subheadline).monospacedDigit()
                            HStack(spacing: 4) {
                                Text(forecastText("Similar intervals"))
                                Text(estimate.observations.count, format: .number)
                                Text("·")
                                Text(forecastText("Days"))
                                Text(estimate.distinctDays, format: .number)
                            }
                            .font(.caption).foregroundStyle(.secondary)
                            if let duration = estimate.usualNapSeconds {
                                Text("\(forecastText("Usual nap length")): \(ForecastFormat.duration(duration.lowerBound))–\(ForecastFormat.duration(duration.upperBound))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } else {
                            Text(cue.state.message).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("forecast-\(cue.kind.rawValue)")
                }
                Text(forecastText("Based on logged routines, not your baby's current needs. Follow your baby's cues and your care plan; do not wait for an estimate to feed or check a diaper."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("activity-forecast-card")
    }
}

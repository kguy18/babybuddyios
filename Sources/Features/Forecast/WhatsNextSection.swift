import SwiftUI

/// What's next on Home, below Today: every estimate with its window and evidence, or the reason
/// it has none. Closed, it is a title row, plus the soonest estimate when the tiles show none.
struct WhatsNextSection: View {
    let snapshot: ForecastSnapshot
    let tilesShown: Bool
    let now: Date
    @AppStorage(ForecastPreferences.sectionOpenKey) private var isOpen = false

    var body: some View {
        BBCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                if isOpen { details }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("whats-next")
    }

    private var header: some View {
        let soonest = snapshot.closedRowEstimate(tilesShown: tilesShown).map { estimate in
            (estimate.kind, ForecastFormat.time(estimate.window.midpoint, now: now))
        }
        return Button {
            withAnimation(.snappy(duration: 0.2)) { isOpen.toggle() }
            Analytics.whatsNextToggled(open: isOpen)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "clock.arrow.circlepath").font(.subheadline)
                Text(forecastText("What's next")).font(.headline)
                Spacer(minLength: 8)
                if !isOpen, let (kind, time) = soonest {
                    Text("\(kind.sectionLabel) ~\(time)")
                        .font(.footnote.weight(.semibold)).monospacedDigit()
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(forecastText("What's next"))
        .accessibilityValue(isOpen ? "" : soonest.map { kind, time in
            String(format: forecastText("%1$@ around %2$@"), kind.sectionLabel, time)
        } ?? "")
        .accessibilityIdentifier("whats-next-toggle")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(snapshot.cues) { cue in
                VStack(alignment: .leading, spacing: 3) {
                    Text(cue.kind.title).font(.subheadline.weight(.semibold))
                    if cue.state == .ready, let estimate = cue.estimate {
                        Text(ForecastFormat.window(estimate.window, now: now)).font(.subheadline).monospacedDigit()
                        HStack(spacing: 4) {
                            Text(forecastText("Similar intervals"))
                            Text(estimate.observations.count, format: .number)
                            Text("·")
                            Text(forecastText("Days"))
                            Text(estimate.distinctDays, format: .number)
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        if let duration = estimate.usualNapSeconds {
                            Text("\(forecastText("Usual nap length")): \(ForecastFormat.duration(duration.lowerBound))\u{2013}\(ForecastFormat.duration(duration.upperBound))")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .bottom], 16)
    }
}

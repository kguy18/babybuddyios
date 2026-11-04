import SwiftUI
import Charts

struct GrowthChartsView: View {
    let entities: [LocalEntity]
    let childID: Int
    let birthDate: Date?
    @State private var period: GrowthPeriod = .all
    @State private var profile = GrowthProfile()
    /// Bundled once, no download or background work. Missing data only removes the overlay.
    private static let reference = WHOGrowthReference.load()

    var body: some View {
        let samples = GrowthCache.samples(entities)
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(growthText("Growth")).font(.title2.bold())
                Spacer()
                NavigationLink {
                    GrowthSettingsView(profile: savedProfile, birthDate: birthDate)
                } label: {
                    Label(growthText("Growth settings"), systemImage: "slider.horizontal.3")
                        .labelStyle(.iconOnly)
                }
                .accessibilityIdentifier("growth-settings")
            }
            BBSegmentedControl(selection: $period, options: GrowthPeriod.allCases, label: \.title,
                               spokenLabel: { "\(growthText("Growth time period")): \($0.title)" })
                .accessibilityElement(children: .contain)
                .accessibilityLabel(growthText("Growth time period"))
            if !profile.unitsConfirmed {
                Text(growthText("Values are shown as recorded. Confirm the stored units in Growth settings to show kg, g and cm."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if profile.showWHO && (profile.referenceBirthDate(birth: birthDate) == nil || Self.reference == nil) {
                Text(growthText("WHO curves need confirmed units, a reference and a valid age basis. Check Growth settings."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(GrowthMetric.allCases) { metric in
                let series = GrowthSeries().samples(samples, childID: childID, metric: metric, period: period)
                let domain = GrowthSeries().xDomain(series, period: period)
                let curves = referencePoints(metric: metric, domain: domain)
                GrowthChartCard(metric: metric, samples: series, profile: profile,
                                domain: domain, reference: curves)
            }
            Text(growthText("Lines connect recorded measurements. Days without measurements are not zero. WHO curves show P3, P15, P50, P85 and P97 for ages 0–1856 days."))
                .font(.caption).foregroundStyle(.secondary)
            if profile.showWHO {
                Text(profile.useCorrectedAge ? growthText("Reference age: corrected age from documented due date")
                     : growthText("Reference age: chronological age"))
                    .font(.caption).foregroundStyle(.secondary)
                if !profile.lengthMethodConfirmed {
                    Text(growthText("Length references are hidden until the measurement method is confirmed."))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text(growthText("Source: WHO Child Growth Standards. Reference curves are for context, not a diagnosis."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { profile = GrowthProfileStore.read(childID: childID) }
        .onChange(of: childID) { _, id in profile = GrowthProfileStore.read(childID: id) }
    }

    private var savedProfile: Binding<GrowthProfile> {
        Binding(get: { profile }, set: {
            profile = $0
            GrowthProfileStore.write($0, childID: childID)
        })
    }

    private func referencePoints(metric: GrowthMetric, domain: ClosedRange<Date>) -> [WHOGrowthReference.Point] {
        guard let birth = profile.referenceBirthDate(birth: birthDate),
              metric != .height || profile.lengthMethodConfirmed else { return [] }
        return Self.reference?.points(metric: metric, sex: profile.referenceSex, birth: birth,
                                      domain: domain, maximumPointsPerCurve: 120) ?? []
    }
}

private struct GrowthChartCard: View {
    let metric: GrowthMetric
    let samples: [GrowthSample]
    let profile: GrowthProfile
    let domain: ClosedRange<Date>
    let reference: [WHOGrowthReference.Point]

    var body: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    ActivityTile(kind: EntityKind(rawValue: metric.rawValue)!, size: 30, glyph: 17)
                    Text(metric.title).font(.headline)
                    Spacer()
                    if let latest = samples.last {
                        Text(GrowthDisplay.value(latest.value, metric: metric, profile: profile))
                            .font(.subheadline).monospacedDigit()
                    }
                }
                if samples.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "chart.xyaxis.line").font(.title2).foregroundStyle(.tertiary)
                        Text(growthText("No measurements in this period"))
                        Text(growthText("Try All, or add a measurement from Home."))
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 168)
                    .accessibilityIdentifier("growth-empty-\(metric.rawValue)")
                } else {
                    GrowthPlot(metric: metric, samples: samples, profile: profile,
                               domain: domain, reference: reference)
                    if let last = samples.last {
                        Text(last.date.formatted(date: .abbreviated, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                NavigationLink {
                    GrowthDetailView(metric: metric, samples: samples, profile: profile,
                                     domain: domain, reference: reference)
                } label: {
                    Label(growthText("View measurements"), systemImage: "list.bullet")
                        .font(.subheadline)
                }
                .accessibilityIdentifier("growth-details-\(metric.rawValue)")
            }
        }
        .accessibilityIdentifier("growth-card-\(metric.rawValue)")
    }
}

private struct GrowthDetailView: View {
    let metric: GrowthMetric
    let samples: [GrowthSample]
    let profile: GrowthProfile
    let domain: ClosedRange<Date>
    let reference: [WHOGrowthReference.Point]

    var body: some View {
        List {
            if samples.isEmpty {
                Text(growthText("No measurements in this period")).foregroundStyle(.secondary)
            } else {
                Section {
                    GrowthPlot(metric: metric, samples: samples, profile: profile,
                               domain: domain, reference: reference)
                }
                Section(growthText("Recorded measurements")) {
                    ForEach(samples.reversed()) { sample in
                        HStack {
                            Text(sample.date.formatted(date: .abbreviated, time: .omitted))
                            Spacer()
                            Text(GrowthDisplay.value(sample.value, metric: metric, profile: profile))
                                .monospacedDigit()
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle(metric.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GrowthPlot: View {
    let metric: GrowthMetric
    let samples: [GrowthSample]
    let profile: GrowthProfile
    let domain: ClosedRange<Date>
    let reference: [WHOGrowthReference.Point]
    @State private var selectedDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(reference) { point in
                    LineMark(x: .value(growthText("Date"), point.date),
                             y: .value(metric.title, profile.referenceDisplay(point.value, metric: metric)),
                             series: .value("Series", point.segment))
                        .foregroundStyle(BBColor.brand.opacity(point.percentile == 50 ? 0.6 : 0.25))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .accessibilityHidden(true)
                }
                ForEach(samples) { sample in
                    LineMark(x: .value(growthText("Date"), sample.date),
                             y: .value(metric.title, profile.display(sample.value, metric: metric)),
                             series: .value("Series", "measurements"))
                        .foregroundStyle(BBColor.brandAccent)
                        .accessibilityHidden(true)
                    PointMark(x: .value(growthText("Date"), sample.date),
                              y: .value(metric.title, profile.display(sample.value, metric: metric)))
                        .foregroundStyle(BBColor.brandAccent)
                        .symbolSize(40)
                        .accessibilityLabel(sample.date.formatted(date: .complete, time: .omitted))
                        .accessibilityValue(GrowthDisplay.value(sample.value, metric: metric, profile: profile))
                }
                if let selected {
                    RuleMark(x: .value(growthText("Date"), selected.date))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: GrowthSeries.yDomain(samples.map { profile.display($0.value, metric: metric) }
                + reference.map { profile.referenceDisplay($0.value, metric: metric) }))
            .chartYAxisLabel(GrowthDisplay.unit(metric: metric, profile: profile))
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(date.formatted(domain.upperBound.timeIntervalSince(domain.lowerBound) > 365 * 86400
                                ? .dateTime.year().month(.abbreviated) : .dateTime.month(.abbreviated).day()))
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedDate)
            .frame(height: 190)
            if let selected {
                Text("\(selected.date.formatted(date: .abbreviated, time: .omitted)): \(GrowthDisplay.value(selected.value, metric: metric, profile: profile))")
                    .font(.caption).monospacedDigit()
            }
            if !reference.isEmpty {
                HStack {
                    ForEach(WHOGrowthReference.percentiles, id: \.self) { Text("P\($0)") }
                }
                .font(.caption2).foregroundStyle(.secondary)
                .accessibilityLabel(growthText("WHO reference percentiles: 3, 15, 50, 85 and 97"))
            }
        }
    }

    private var selected: GrowthSample? {
        guard let selectedDate else { return nil }
        return samples.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }
}

private enum GrowthDisplay {
    static func unit(metric: GrowthMetric, profile: GrowthProfile) -> String {
        guard profile.unitsConfirmed else { return growthText("Recorded value") }
        return metric == .weight ? profile.displayWeightUnit.symbol : "cm"
    }
    static func value(_ value: Double, metric: GrowthMetric, profile: GrowthProfile) -> String {
        let number = profile.display(value, metric: metric)
            .formatted(.number.precision(.fractionLength(0...3)))
        return profile.unitsConfirmed ? "\(number) \(unit(metric: metric, profile: profile))" : number
    }
}

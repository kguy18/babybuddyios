import SwiftUI
import SwiftData
import Charts

/// Read-only trends for the selected child over a selectable rolling window — the native
/// counterpart to the Baby Buddy web dashboard charts. Aggregates entirely from the local
/// cache via ``ChartAggregator``; no network is required.
struct InsightsView: View {
    @Environment(SyncEngine.self) private var sync
    @Binding var selectedChildID: Int

    /// Only the kinds the charts aggregate, scoped to the selected child store-side, so a save
    /// elsewhere in the store doesn't rebuild the charts over the whole table. Rebuilt on child
    /// switch via `init`.
    @Query private var chartEntities: [LocalEntity]
    @Query(filter: #Predicate<LocalEntity> { $0.kindRaw == "child" }, sort: \.timestamp)
    private var children: [LocalEntity]
    @State private var period: ChartPeriod = .week
    @State private var colors = MedicineColorStore.shared
    // Watched so the temperature card follows Settings ▸ Sick mode; the keys and defaults are the
    // ones ``SickMode`` reads.
    @AppStorage(TemperatureUnit.key, store: SharedDefaults.suite) private var storedUnit: TemperatureUnit?
    @AppStorage(SickMode.feverLineKey, store: SharedDefaults.suite) private var feverLineCelsius = SickMode.defaultFeverLine

    private let aggregator = ChartAggregator()

    /// Whether `Insights.viewed` has been sent on arrival this launch.
    private static var viewedThisLaunch = false

    init(selectedChildID: Binding<Int>) {
        _selectedChildID = selectedChildID
        let child = selectedChildID.wrappedValue
        let kinds = [EntityKind.sleep, .feeding, .change, .tummyTime, .pumping,
                     .temperature, .medication, .weight, .height, .headCircumference].map(\.rawValue)
        let pendingDelete = SyncState.pendingDelete.rawValue
        let predicate = #Predicate<LocalEntity> { entity in
            entity.childID == child && kinds.contains(entity.kindRaw)
                && entity.syncStateRaw != pendingDelete
        }
        _chartEntities = Query(filter: predicate, sort: \LocalEntity.timestamp, order: .reverse)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BBSegmentedControl(selection: $period,
                                       options: ChartPeriod.allCases,
                                       label: \.accessibilityLabel)
                        // `.contain` first: a label on the bare control is stamped onto every
                        // segment, which read all three to VoiceOver as "Time period".
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel("Time period")

                    sleepCard
                    feedingCard
                    diaperCard
                    tummyTimeCard
                    pumpingCard
                    temperatureCard
                    GrowthChartsView(entities: chartEntities, childID: selectedChildID, birthDate: growthBirthDate)
                        .id(selectedChildID)
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(BBColor.surface)
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ChildSwitcher(children: children, selectedChildID: $selectedChildID) }
            .refreshable { await sync.sync() }
            // Whether Trends earns its place in the tab bar, which window people actually reach
            // for, and how often the temperature card has a spell to draw over it. Fires on the
            // first arrival each launch and on every change of the segmented control. Switching
            // back to the tab again only repeats the first signal, so it isn't sent.
            .onAppear {
                guard !Self.viewedThisLaunch else { return }
                Self.viewedThisLaunch = true
                Analytics.insightsViewed(periodDays: period.days,
                                         temperature: temperatureChart(period))
            }
            .onChange(of: period) { _, newPeriod in
                Analytics.insightsViewed(periodDays: newPeriod.days,
                                         temperature: temperatureChart(newPeriod))
            }
            .overlay {
                if children.isEmpty {
                    ContentUnavailableView(
                        "No Children", systemImage: "person.crop.circle.badge.questionmark",
                        description: Text("Add a child in Baby Buddy to see trends."))
                }
            }
        }
    }

    // MARK: Sleep

    private var sleepCard: some View {
        let series = aggregator.sleepHoursByDay(chartEntities, childID: selectedChildID, period: period)
        let total = series.reduce(0) { $0 + $1.hours }
        let hasData = total > 0
        return ChartCard(title: "Sleep", icon: .sleep,
                         summary: hasData ? "Avg \(oneDecimal(total / Double(series.count)))h / day" : nil) {
            if hasData {
                Chart(series) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Hours", day.hours))
                    .foregroundStyle(BBColor.sleep)
                    .cornerRadius(3)
                    .accessibilityLabel(dayLabel(day.day))
                    .accessibilityValue("\(oneDecimal(day.hours)) hours")
                }
                .chartYAxisLabel("Hours")
                .modifier(DayAxis(period: period))
                .frame(height: chartHeight)
            } else {
                emptyChart("No sleep logged")
            }
        }
    }

    // MARK: Feeding

    private var feedingCard: some View {
        let series = aggregator.feedingsByDay(chartEntities, childID: selectedChildID, period: period)
        let totalCount = series.reduce(0) { $0 + $1.count }
        let hasData = totalCount > 0
        let hasAmounts = series.contains { $0.totalAmount > 0 }
        return ChartCard(title: "Feedings", icon: .feeding,
                         summary: hasData ? "Avg \(oneDecimal(Double(totalCount) / Double(series.count))) / day" : nil) {
            if hasData {
                VStack(alignment: .leading, spacing: 14) {
                    Chart(series) { day in
                        BarMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Feedings", day.count))
                        .foregroundStyle(BBColor.feeding)
                        .cornerRadius(3)
                        .accessibilityLabel(dayLabel(day.day))
                        .accessibilityValue("\(day.count) feedings")
                    }
                    .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .modifier(DayAxis(period: period))
                    .frame(height: chartHeight)

                    if hasAmounts {
                        Divider().overlay(BBColor.divider)
                        Text("Amount (ml)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Chart(series) { day in
                            BarMark(
                                x: .value("Day", day.day, unit: .day),
                                y: .value("Amount", day.totalAmount))
                            .foregroundStyle(BBColor.feeding.opacity(0.55))
                            .cornerRadius(3)
                            .accessibilityLabel(dayLabel(day.day))
                            .accessibilityValue("\(Int(day.totalAmount)) millilitres")
                        }
                        .modifier(DayAxis(period: period))
                        .frame(height: chartHeight * 0.8)
                    }
                }
            } else {
                emptyChart("No feedings logged")
            }
        }
    }

    // MARK: Diaper changes

    /// One stacked segment (wet or solid) for a single day.
    private struct DiaperPoint: Identifiable {
        let day: Date
        let kind: String
        let count: Int
        var id: String { "\(day.timeIntervalSince1970)-\(kind)" }
    }

    private var diaperCard: some View {
        let series = aggregator.diaperChangesByDay(chartEntities, childID: selectedChildID, period: period)
        let totalWet = series.reduce(0) { $0 + $1.wet }
        let totalSolid = series.reduce(0) { $0 + $1.solid }
        let hasData = totalWet + totalSolid > 0
        let points = series.flatMap {
            [DiaperPoint(day: $0.day, kind: "Wet", count: $0.wet),
             DiaperPoint(day: $0.day, kind: "Solid", count: $0.solid)]
        }
        return ChartCard(title: "Diapers", icon: .change,
                         summary: hasData ? "\(totalWet) wet · \(totalSolid) solid" : nil) {
            if hasData {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Changes", point.count))
                    .foregroundStyle(by: .value("Type", point.kind))
                    .cornerRadius(3)
                    .accessibilityLabel(dayLabel(point.day))
                    .accessibilityValue("\(point.count) \(point.kind.lowercased())")
                }
                .chartForegroundStyleScale(["Wet": BBColor.info, "Solid": BBColor.change])
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .modifier(DayAxis(period: period))
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: chartHeight)
            } else {
                emptyChart("No diaper changes logged")
            }
        }
    }

    // MARK: Tummy time

    private var tummyTimeCard: some View {
        let series = aggregator.tummyTimeMinutesByDay(chartEntities, childID: selectedChildID, period: period)
        let total = series.reduce(0) { $0 + $1.minutes }
        let hasData = total > 0
        return ChartCard(title: "Tummy Time", icon: .tummyTime,
                         summary: hasData ? "Avg \(Int(total / Double(series.count))) min / day" : nil) {
            if hasData {
                Chart(series) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Minutes", day.minutes))
                    .foregroundStyle(BBColor.tummy)
                    .cornerRadius(3)
                    .accessibilityLabel(dayLabel(day.day))
                    .accessibilityValue("\(Int(day.minutes)) minutes")
                }
                .chartYAxisLabel("Minutes")
                .modifier(DayAxis(period: period))
                .frame(height: chartHeight)
            } else {
                emptyChart("No tummy time logged")
            }
        }
    }

    // MARK: Pumping

    private var pumpingCard: some View {
        let series = aggregator.pumpingByDay(chartEntities, childID: selectedChildID, period: period)
        let totalCount = series.reduce(0) { $0 + $1.count }
        let totalAmount = series.reduce(0) { $0 + $1.totalAmount }
        let hasData = totalCount > 0
        return ChartCard(title: "Pumping", icon: .pumping,
                         summary: hasData ? "Avg \(Int(totalAmount / Double(series.count))) ml / day" : nil) {
            if hasData {
                VStack(alignment: .leading, spacing: 14) {
                    Chart(series) { day in
                        BarMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Amount", day.totalAmount))
                        .foregroundStyle(BBColor.pumping)
                        .cornerRadius(3)
                        .accessibilityLabel(dayLabel(day.day))
                        .accessibilityValue("\(Int(day.totalAmount)) millilitres")
                    }
                    .chartYAxisLabel("ml")
                    .modifier(DayAxis(period: period))
                    .frame(height: chartHeight)

                    Divider().overlay(BBColor.divider)
                    Text("Sessions")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Chart(series) { day in
                        BarMark(
                            x: .value("Day", day.day, unit: .day),
                            y: .value("Sessions", day.count))
                        .foregroundStyle(BBColor.pumping.opacity(0.55))
                        .cornerRadius(3)
                        .accessibilityLabel(dayLabel(day.day))
                        .accessibilityValue("\(day.count) sessions")
                    }
                    .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                    .modifier(DayAxis(period: period))
                    .frame(height: chartHeight * 0.8)
                }
            } else {
                emptyChart("No pumping logged")
            }
        }
    }

    // MARK: Temperature

    /// A sick spell as one picture (#79): every reading over the window, the fever line dashed
    /// across it, and a marker where each dose was given in that medicine's color. Unlike the other
    /// cards this one plots the records at their own times rather than a total per day. A fever is
    /// read by its shape over hours, and the doses have to line up with it.
    private var temperatureCard: some View {
        let now = Date.now
        let readings = aggregator.temperatures(chartEntities, childID: selectedChildID,
                                               period: period, unit: unit, now: now)
        let doses = aggregator.doses(chartEntities, childID: selectedChildID, period: period, now: now)
        let peak = readings.max { $0.value < $1.value }
        return ChartCard(title: "Temperature", icon: .temperature,
                         summary: peak.map { "Peak \(unit.format($0.value))" }) {
            if readings.isEmpty {
                emptyChart("No temperatures logged")
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    Chart {
                        ForEach(doses, id: \.localID) { dose in
                            RuleMark(x: .value("Dose", dose.timestamp))
                                .lineStyle(StrokeStyle(lineWidth: 1.5))
                                .foregroundStyle(doseColor(dose).opacity(0.5))
                                .accessibilityLabel(doseName(dose))
                                .accessibilityValue(doseValue(dose))
                        }
                        RuleMark(y: .value("Fever", feverLine))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .foregroundStyle(BBColor.danger.opacity(0.7))
                            .accessibilityLabel("Fever line")
                            .accessibilityValue(unit.format(feverLine))
                        ForEach(readings, id: \.entity.localID) { reading in
                            LineMark(
                                x: .value("Time", reading.time),
                                y: .value("Temperature", reading.value))
                            .foregroundStyle(BBColor.brand)
                            .symbol(.circle)
                            .symbolSize(26)
                            .accessibilityLabel(momentLabel(reading.time))
                            .accessibilityValue(unit.format(reading.value))
                        }
                    }
                    .chartYAxisLabel(unit.symbol)
                    // Charts would otherwise anchor the axis at 0 and flatten a fever into a
                    // straight line. The margins are the sick card's, so both read the same shape.
                    .chartYScale(domain: temperatureDomain(readings))
                    // No x scale of its own. The marks carry their own times and the period control
                    // decides what's included, so a spell of hours fills the card as a fortnight
                    // does. The labels follow the same way, clock times while it all fits in a day
                    // and a half. Charts' own date labels carry both and clip to "Sep 22…".
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisTick()
                            AxisValueLabel {
                                if let date = value.as(Date.self) {
                                    Text(date.formatted(spansDays(readings, doses)
                                        ? .dateTime.month(.abbreviated).day() : .dateTime.hour()))
                                }
                            }
                        }
                    }
                    .frame(height: chartHeight)

                    Text("Fever line at \(unit.format(feverLine))")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(aggregator.doseTallies(doses)) { tally in
                        HStack(spacing: 7) {
                            Circle().fill(colors.color(tally.id).color).frame(width: 8, height: 8)
                            Text(tally.name).font(.caption.weight(.medium))
                            Text("\(tally.count) dose\(tally.count == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var unit: TemperatureUnit { storedUnit ?? .region }
    private var feverLine: Double { unit.convert(feverLineCelsius, from: .celsius) }

    /// Whether the card draws a chart or its empty state over `period`, for ``Analytics``. The card
    /// is the last one on the screen, so how often it has anything to show is what says where it
    /// belongs.
    private func temperatureChart(_ period: ChartPeriod) -> Analytics.TemperatureChart {
        aggregator.temperatures(chartEntities, childID: selectedChildID, period: period, unit: unit)
            .isEmpty ? .empty : .drawn
    }

    /// Whether the marks reach over more than a day and a half, and so want dates on the x axis.
    private func spansDays(_ readings: [SickMode.Reading], _ doses: [LocalEntity]) -> Bool {
        let times = readings.map(\.time) + doses.map(\.timestamp)
        guard let first = times.min(), let last = times.max() else { return false }
        return last.timeIntervalSince(first) > 36 * 3600
    }

    /// The readings and the fever line, with room around them, over a span of at least two degrees
    /// (one in °C) so a steady temperature isn't magnified into a mountain range.
    private func temperatureDomain(_ readings: [SickMode.Reading]) -> ClosedRange<Double> {
        let values = readings.map(\.value) + [feverLine]
        let low = values.min()!, high = values.max()!
        let span = max(high - low, unit == .fahrenheit ? 2 : 1.1)
        return (low - span * 0.25)...(high + span * 0.15)
    }

    private func doseColor(_ dose: LocalEntity) -> Color {
        colors.color(dose.payloadObject["name"] as? String ?? "").color
    }

    private func doseName(_ dose: LocalEntity) -> String {
        let name = (dose.payloadObject["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Medication" : name
    }

    /// "5 mL, Jun 14 at 3:30 PM". A dose marker sits on no axis of its own, so it reads its time out.
    private func doseValue(_ dose: LocalEntity) -> String {
        [EntityFormatting.dosage(dose), momentLabel(dose.timestamp)]
            .compactMap { $0 }.joined(separator: ", ")
    }

    private var growthBirthDate: Date? {
        guard let raw = children.first(where: { $0.serverID == selectedChildID })?
            .payloadObject["birth_date"] as? String else { return nil }
        return GrowthDate.parse(raw)
    }

    // MARK: Helpers

    private let chartHeight: CGFloat = 168

    private func oneDecimal(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func dayLabel(_ day: Date) -> String {
        day.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Jun 14 at 3:30 PM", for a mark that sits at a time rather than on a day.
    private func momentLabel(_ date: Date) -> String {
        "\(dayLabel(date)) at \(date.formatted(date: .omitted, time: .shortened))"
    }

    private func emptyChart(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2).foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: chartHeight)
    }
}

// MARK: - Chart card

/// A titled card wrapping a chart, matching the design-system card look.
private struct ChartCard<Content: View>: View {
    let title: String
    let icon: EntityKind
    let summary: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    ActivityTile(kind: icon, size: 30, glyph: 17)
                    Text(title).font(.headline)
                    Spacer(minLength: 8)
                    if let summary {
                        Text(summary)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
                content()
            }
        }
    }
}

// MARK: - Shared day axis

/// Consistent x-axis across the charts: fewer labels as the window widens, so ticks stay
/// legible and Dynamic Type-friendly. 7 days shows weekday initials; wider windows show the
/// day of the month.
private struct DayAxis: ViewModifier {
    let period: ChartPeriod

    func body(content: Content) -> some View {
        content.chartXAxis {
            AxisMarks(values: .stride(by: .day, count: stride)) { value in
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(date.formatted(labelFormat))
                    }
                }
            }
        }
    }

    private var stride: Int {
        switch period {
        case .week: return 1
        case .twoWeeks: return 2
        case .month: return 5
        }
    }

    private var labelFormat: Date.FormatStyle {
        period == .week ? .dateTime.weekday(.narrow) : .dateTime.day()
    }
}

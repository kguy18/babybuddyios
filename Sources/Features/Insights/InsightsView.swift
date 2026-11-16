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
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The panes either side of the fold on iPhone Duo's open display, or nil for one column.
    @State private var foldPanes: FoldLayout.Panes?
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
                     .temperature, .medication].map(\.rawValue)
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
                cardLayout {
                    periodPicker

                    sleepCard
                    feedingCard
                    diaperCard
                    tummyTimeCard
                    pumpingCard
                    temperatureCard
                }
                .padding(.horizontal)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .onGeometryChange(for: FoldLayout.Panes?.self) { geometry in
                FoldLayout.panes(width: geometry.size.width, fold: Self.fold(in: geometry))
            } action: { foldPanes = $0 }
            .background(BBColor.surface)
            .navigationTitle("Trends")
            .accessibilityIdentifier("screen-trends")
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

    /// One column, or on the open display a column each side of the fold: one column across it
    /// ran the fold through every chart.
    private var cardLayout: AnyLayout {
        foldPanes.map { AnyLayout(FoldColumns(panes: $0, margin: 16, spacing: 16)) }
            ?? AnyLayout(VStackLayout(spacing: 16))
    }

    /// The fold, from the system's reserved regions, as ``FoldSplitView`` finds it.
    private static func fold(in geometry: GeometryProxy) -> CGRect? {
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            return geometry.reservedRegions(kind: .division, options: .includeInactive)
                .first { $0.frame.height > $0.frame.width }?.frame
        }
        #endif
        return nil
    }

    @ViewBuilder private var periodPicker: some View {
        if typeSize.isAccessibilitySize {
            // At these sizes the three segments truncate ("7 da…"), so a menu names the chosen one
            // in full.
            Picker("Time period", selection: $period) {
                ForEach(ChartPeriod.allCases) { Text($0.accessibilityLabel).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            BBSegmentedControl(selection: $period,
                               options: ChartPeriod.allCases,
                               label: \.accessibilityLabel)
                // `.contain` first: a label on the bare control is stamped onto every
                // segment, which read all three to VoiceOver as "Time period".
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Time period")
        }
    }

    // MARK: Sleep

    private var sleepCard: some View {
        let series = aggregator.sleepHoursByDay(chartEntities, childID: selectedChildID, period: period)
        let total = series.reduce(0) { $0 + $1.hours }
        let hasData = total > 0
        return ChartCard(title: String(localized: "Sleep"), icon: .sleep,
                         summary: hasData ? String(localized: "Avg \(oneDecimal(total / Double(series.count)))h / day") : nil) {
            if hasData {
                Chart(series) { day in
                    BarMark(
                        x: .value("Day", day.day, unit: .day),
                        y: .value("Hours", day.hours))
                    .foregroundStyle(BBColor.sleep)
                    .cornerRadius(3)
                    .accessibilityLabel(dayLabel(day.day))
                    .accessibilityValue(EntityFormatting.spokenDuration(day.hours * 3600))
                }
                .chartYAxisLabel("Hours")
                .modifier(DayAxis(period: period))
                .frame(height: chartHeight)
            } else {
                emptyChart(String(localized: "No sleep logged"))
            }
        }
    }

    // MARK: Feeding

    private var feedingCard: some View {
        let series = aggregator.feedingsByDay(chartEntities, childID: selectedChildID, period: period)
        let totalCount = series.reduce(0) { $0 + $1.count }
        let hasData = totalCount > 0
        let hasAmounts = series.contains { $0.totalAmount > 0 }
        return ChartCard(title: String(localized: "Feedings"), icon: .feeding,
                         summary: hasData ? String(localized: "Avg \(oneDecimal(Double(totalCount) / Double(series.count))) / day") : nil) {
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
                emptyChart(String(localized: "No feedings logged"))
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
            [DiaperPoint(day: $0.day, kind: String(localized: "Wet"), count: $0.wet),
             DiaperPoint(day: $0.day, kind: String(localized: "Solid"), count: $0.solid)]
        }
        return ChartCard(title: String(localized: "Diapers"), icon: .change,
                         summary: hasData ? String(localized: "\(totalWet) wet · \(totalSolid) solid") : nil) {
            if hasData {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", point.day, unit: .day),
                        y: .value("Changes", point.count))
                    .foregroundStyle(by: .value("Type", point.kind))
                    .cornerRadius(3)
                    .accessibilityLabel(dayLabel(point.day))
                    .accessibilityValue(point.kind == String(localized: "Wet")
                        ? String(localized: "\(point.count) wet changes")
                        : String(localized: "\(point.count) solid changes"))
                }
                .chartForegroundStyleScale([String(localized: "Wet"): BBColor.info, String(localized: "Solid"): BBColor.change])
                .chartYAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .modifier(DayAxis(period: period))
                .chartLegend(position: .bottom, spacing: 8)
                .frame(height: chartHeight)
            } else {
                emptyChart(String(localized: "No diaper changes logged"))
            }
        }
    }

    // MARK: Tummy time

    private var tummyTimeCard: some View {
        let series = aggregator.tummyTimeMinutesByDay(chartEntities, childID: selectedChildID, period: period)
        let total = series.reduce(0) { $0 + $1.minutes }
        let hasData = total > 0
        return ChartCard(title: String(localized: "Tummy Time"), icon: .tummyTime,
                         summary: hasData ? String(localized: "Avg \(Int(total / Double(series.count))) min / day") : nil) {
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
                emptyChart(String(localized: "No tummy time logged"))
            }
        }
    }

    // MARK: Pumping

    private var pumpingCard: some View {
        let series = aggregator.pumpingByDay(chartEntities, childID: selectedChildID, period: period)
        let totalCount = series.reduce(0) { $0 + $1.count }
        let totalAmount = series.reduce(0) { $0 + $1.totalAmount }
        let hasData = totalCount > 0
        return ChartCard(title: String(localized: "Pumping"), icon: .pumping,
                         summary: hasData ? String(localized: "Avg \(Int(totalAmount / Double(series.count))) ml / day") : nil) {
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
                emptyChart(String(localized: "No pumping logged"))
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
        return ChartCard(title: String(localized: "Temperature"), icon: .temperature,
                         summary: peak.map { String(localized: "Peak \(unit.format($0.value))") }) {
            if readings.isEmpty {
                emptyChart(String(localized: "No temperatures logged"))
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
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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
                            // Beside the count a long name broke mid-word ("Aceta / minophe") at
                            // accessibility sizes, so there the count goes under it.
                            tallyLayout {
                                Text(tally.name).font(.caption.weight(.medium))
                                Text("\(tally.count) doses")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private var tallyLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 7))
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
        return name.isEmpty ? String(localized: "Medication") : name
    }

    /// "5 mL, Jun 14 at 3:30 PM". A dose marker sits on no axis of its own, so it reads its time out.
    private func doseValue(_ dose: LocalEntity) -> String {
        [EntityFormatting.dosage(dose), momentLabel(dose.timestamp)]
            .compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: Helpers

    private let chartHeight: CGFloat = 168

    private func oneDecimal(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : value.formatted(.number.precision(.fractionLength(1)).grouping(.never))
    }

    private func dayLabel(_ day: Date) -> String {
        day.formatted(.dateTime.month(.abbreviated).day())
    }

    /// "Jun 14 at 3:30 PM", for a mark that sits at a time rather than on a day.
    private func momentLabel(_ date: Date) -> String {
        String(localized: "\(dayLabel(date)) at \(date.formatted(date: .omitted, time: .shortened))")
    }

    private func emptyChart(_ message: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2).foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        // At least a chart's height, so it can grow when the message wraps at large text.
        .frame(minHeight: chartHeight)
    }
}

// MARK: - Chart card

/// A titled card wrapping a chart, matching the design-system card look.
private struct ChartCard<Content: View>: View {
    let title: String
    let icon: EntityKind
    let summary: String?
    @ViewBuilder let content: () -> Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                if typeSize.isAccessibilitySize {
                    // Beside the summary the title broke mid-word ("Slee / p"), so at these sizes
                    // the summary goes under it, and the tile goes, as it does on Home.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).font(.headline)
                        summaryText
                    }
                } else {
                    HStack(spacing: 9) {
                        ActivityTile(kind: icon, size: 30, glyph: 17)
                        Text(title).font(.headline)
                        Spacer(minLength: 8)
                        summaryText
                    }
                }
                content()
            }
        }
    }

    @ViewBuilder private var summaryText: some View {
        if let summary {
            Text(summary)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Fold columns

/// The cards on iPhone Duo's open display: a column each side of the fold, each card going under
/// whichever column is shorter so far, so neither runs far past the other. The container sits
/// `margin` in from each edge of the screen, and each column keeps that margin from the fold too.
private struct FoldColumns: Layout {
    let panes: FoldLayout.Panes
    let margin: CGFloat
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let height = frames(subviews).map(\.maxY).max() ?? 0
        return CGSize(width: proposal.width ?? panes.side + panes.fold + panes.main - 2 * margin, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(_ subviews: Subviews) -> [CGRect] {
        let columns: [(x: CGFloat, width: CGFloat)] = [(x: 0, width: panes.side - 2 * margin),
                                                       (x: panes.side + panes.fold, width: panes.main - 2 * margin)]
        var bottoms: [CGFloat] = [-spacing, -spacing]
        return subviews.map { subview in
            let index = bottoms[0] <= bottoms[1] ? 0 : 1
            let column = columns[index]
            let height = subview.sizeThatFits(ProposedViewSize(width: column.width, height: nil)).height
            let frame = CGRect(x: column.x, y: bottoms[index] + spacing, width: column.width, height: height)
            bottoms[index] = frame.maxY
            return frame
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
        // Past this size the axis labels piled on top of each other ("15 10 5 0") in the chart's
        // fixed height. Each chart's values are in its marks' VoiceOver labels.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
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

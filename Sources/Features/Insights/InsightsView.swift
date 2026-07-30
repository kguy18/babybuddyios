import SwiftUI
import SwiftData
import Charts

/// Read-only trends for the selected child over a selectable rolling window — the native
/// counterpart to the Baby Buddy web dashboard charts. Aggregates entirely from the local
/// cache via ``ChartAggregator``; no network is required.
struct InsightsView: View {
    @Environment(SyncEngine.self) private var sync
    @Binding var selectedChildID: Int

    @Query(sort: \LocalEntity.timestamp, order: .reverse) private var allEntities: [LocalEntity]
    @State private var period: ChartPeriod = .week

    private let aggregator = ChartAggregator()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    BBSegmentedControl(selection: $period,
                                       options: ChartPeriod.allCases,
                                       label: \.accessibilityLabel)
                        .accessibilityLabel("Time period")

                    sleepCard
                    feedingCard
                    diaperCard
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
            // Whether Trends earns its place in the tab bar, and which window people actually
            // reach for. Fires on arrival and on every change of the segmented control — the tab
            // has one screen and one parameter, so those two are the whole picture.
            .onAppear { Analytics.insightsViewed(periodDays: period.days) }
            .onChange(of: period) { _, newPeriod in
                Analytics.insightsViewed(periodDays: newPeriod.days)
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
        let series = aggregator.sleepHoursByDay(allEntities, childID: selectedChildID, period: period)
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
        let series = aggregator.feedingsByDay(allEntities, childID: selectedChildID, period: period)
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
        let series = aggregator.diaperChangesByDay(allEntities, childID: selectedChildID, period: period)
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

    // MARK: Helpers

    private var children: [LocalEntity] { allEntities.filter { $0.kind == .child } }

    private let chartHeight: CGFloat = 168

    private func oneDecimal(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    private func dayLabel(_ day: Date) -> String {
        day.formatted(.dateTime.month(.abbreviated).day())
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

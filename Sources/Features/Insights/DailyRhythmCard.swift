import SwiftUI
import Charts

struct DailyRhythmCard: View {
    let entities: [LocalEntity]
    let childID: Int
    let period: ChartPeriod
    @State private var selected: RhythmDay?
    @ScaledMetric(relativeTo: .caption) private var rowHeight: CGFloat = 32

    private var rows: [RhythmDay] {
        DailyRhythmAggregator().days(entities, childID: childID, period: period)
    }

    var body: some View {
        let days = rows
        BBCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Daily rhythm", systemImage: "clock").font(.headline)
                if days.allSatisfy({ $0.sleeps.isEmpty && $0.feedings.isEmpty }) {
                    ContentUnavailableView("No sleep or feedings logged", systemImage: "chart.bar.xaxis")
                } else {
                    chart(days)
                    HStack(spacing: 16) {
                        Label("Sleep", systemImage: "rectangle.fill").foregroundStyle(BBColor.sleep)
                        Label("Feedings", systemImage: "circle.fill").foregroundStyle(BBColor.feeding)
                    }
                    .font(.caption)
                    Text("Local clock time. Sleep is split at midnight and clock changes; feedings mark their start.")
                        .font(.caption).foregroundStyle(.secondary)
                    Menu("Show daily details", systemImage: "list.bullet") {
                        ForEach(days) { day in
                            Button(day.day.formatted(date: .abbreviated, time: .omitted)) { selected = day }
                                .accessibilityIdentifier(day.id == days.last?.id ? "rhythm-today" : "rhythm-day-\(day.axisID)")
                        }
                    }
                    .font(.subheadline)
                    .accessibilityIdentifier("rhythm-details")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daily-rhythm")
        .onChange(of: childID) { _, _ in selected = nil }
        .onChange(of: period) { _, _ in selected = nil }
        .sheet(item: $selected) { day in details(day) }
    }

    private func chart(_ days: [RhythmDay]) -> some View {
        Chart {
            ForEach(days) { day in
                ForEach(day.sleeps) { sleep in
                    RectangleMark(xStart: .value("Time", sleep.startHour), xEnd: .value("Time", sleep.endHour),
                                  y: .value("Day", day.axisID), height: .ratio(0.55))
                        .foregroundStyle(BBColor.sleep)
                        .accessibilityLabel(String(localized: "Sleep"))
                        .accessibilityValue(interval(sleep))
                }
                ForEach(day.feedings) { feeding in
                    PointMark(x: .value("Time", feeding.hour), y: .value("Day", day.axisID))
                        .foregroundStyle(BBColor.feeding)
                        .symbolSize(28)
                        .accessibilityLabel(String(localized: "Feeding"))
                        .accessibilityValue(feeding.time.formatted(date: .abbreviated, time: .shortened))
                }
            }
        }
        .chartXScale(domain: 0...24)
        .chartYScale(domain: days.map(\.axisID).reversed())
        .chartXAxis {
            AxisMarks(values: [0, 6, 12, 18, 24]) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let hour = value.as(Int.self) { Text(String(format: "%02d:00", hour)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: days.map(\.axisID)) { value in
                AxisGridLine()
                AxisValueLabel {
                    if let id = value.as(String.self), let day = days.first(where: { $0.axisID == id }) {
                        Text(day.day.formatted(.dateTime.day().month(.twoDigits)))
                    }
                }
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Color.clear.contentShape(Rectangle())
                    .gesture(SpatialTapGesture().onEnded { tap in
                        guard let anchor = proxy.plotFrame else { return }
                        let plot = geometry[anchor]
                        guard plot.contains(tap.location),
                              let id: String = proxy.value(atY: tap.location.y - plot.minY) else { return }
                        selected = days.first { $0.axisID == id }
                    })
                    .accessibilityHidden(true)
            }
        }
        .frame(height: CGFloat(days.count) * rowHeight + 30)
        .accessibilityIdentifier("rhythm-chart")
    }

    private func details(_ day: RhythmDay) -> some View {
        NavigationStack {
            List {
                Section("Sleep") {
                    if day.sleeps.isEmpty { Text("No sleep logged") }
                    ForEach(day.sleeps) { sleep in
                        VStack(alignment: .leading) {
                            Text(interval(sleep))
                            Text(EntityFormatting.spokenDuration(sleep.end.timeIntervalSince(sleep.start)))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Section("Feedings") {
                    if day.feedings.isEmpty { Text("No feedings logged") }
                    ForEach(day.feedings) { feeding in
                        VStack(alignment: .leading) {
                            Text(feeding.time.formatted(date: .omitted, time: .shortened))
                            if let method = feeding.method { Text(method.label).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            .navigationTitle(day.day.formatted(date: .abbreviated, time: .omitted))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { selected = nil } } }
        }
    }

    private func interval(_ sleep: RhythmSleep) -> String {
        sleep.start.formatted(date: .abbreviated, time: .shortened) + " – "
            + sleep.end.formatted(date: .abbreviated, time: .shortened)
    }
}

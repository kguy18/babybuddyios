import SwiftUI
import Charts

struct TrendValue: Identifiable, Equatable {
    let date: Date
    let text: String
    var recordID: UUID? = nil
    var id: String { recordID?.uuidString ?? String(date.timeIntervalSince1970) }

    static func selected(at date: Date, in values: [TrendValue], daily: Bool,
                         calendar: Calendar = .current) -> TrendValue? {
        if daily { return values.first { calendar.isDate($0.date, inSameDayAs: date) } }
        // The caller already restricts taps to the plot. Charts pads the time domain, especially
        // for a single reading, so allow those margins to select the nearest actual reading.
        return values.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
    }

    static func amount(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...6)))
    }
}

/// A tap recognizer leaves vertical scrolling to the surrounding ScrollView. The same values
/// are offered as a list for VoiceOver and for days whose bars are too small to target.
struct ChartValueDetails: ViewModifier {
    let values: [TrendValue]
    let identifier: String
    var daily = true
    @State private var selected: TrendValue?
    @State private var showingValues = false

    func body(content: Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content
                .accessibilityIdentifier("\(identifier)-chart")
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        Color.clear.contentShape(Rectangle())
                            .gesture(SpatialTapGesture().onEnded { tap in
                                guard let anchor = proxy.plotFrame else { return }
                                let plot = geometry[anchor]
                                guard plot.contains(tap.location),
                                      let date: Date = proxy.value(atX: tap.location.x - plot.minX) else { return }
                                selected = TrendValue.selected(at: date, in: values, daily: daily)
                            })
                            .accessibilityHidden(true)
                    }
                }
            if let selected {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label(selected.date)).font(.caption.weight(.semibold))
                    Text(selected.text).font(.subheadline).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("\(identifier)-selected-value")
            }
            Button("Show values", systemImage: "list.bullet") { showingValues = true }
                .font(.caption)
                .accessibilityIdentifier("\(identifier)-values")
        }
        .onChange(of: values) { _, _ in selected = nil }
        .sheet(isPresented: $showingValues) {
            NavigationStack {
                List(values) { value in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label(value.date)).font(.subheadline.weight(.medium))
                        Text(value.text).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
                .navigationTitle("Chart values")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showingValues = false }
                } }
            }
        }
    }

    private func label(_ date: Date) -> String {
        daily ? date.formatted(date: .abbreviated, time: .omitted)
            : date.formatted(date: .abbreviated, time: .shortened)
    }
}

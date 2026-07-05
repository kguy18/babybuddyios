import WidgetKit
import SwiftUI
import SwiftData

/// At-a-glance status of the selected child: when they last fed / slept / were changed (live
/// relative times) plus today's counts. Home Screen (small/medium) and Lock Screen / StandBy
/// accessories. Read-only — it fetches the shared cache the app keeps fresh; no network.
struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BabyBuddyStatus", provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Child status")
        .description("See when your child last fed, slept, and was changed, plus today's counts.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryInline, .accessoryCircular, .accessoryRectangular,
        ])
    }
}

struct StatusEntry: TimelineEntry {
    let date: Date
    let status: ChildStatus
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, status: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        let status = context.isPreview ? .sample : Self.currentStatus()
        completion(StatusEntry(date: .now, status: status))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        // Relative times refresh themselves via `Text(_, style: .relative)`; the counts are
        // computed here, so ask WidgetKit to refresh in ~30 min to keep them (and the midnight
        // rollover) current. The app also reloads timelines whenever it writes a record.
        let entry = StatusEntry(date: .now, status: Self.currentStatus())
        let next = Date.now.addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    /// Status of the selected child from the shared store, or `.unavailable` if none/no store.
    static func currentStatus() -> ChildStatus {
        guard let container = try? ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: LocalStore.storeURL))
        else { return .unavailable }
        let context = ModelContext(container)
        let entities = (try? context.fetch(FetchDescriptor<LocalEntity>())) ?? []
        return ChildStatus.compute(from: entities, childID: SharedDefaults.selectedChildID)
    }
}

// MARK: - Sample (previews / placeholder)

extension ChildStatus {
    static let sample = ChildStatus(
        hasChild: true, childName: "Ada",
        feeding: KindStatus(kind: .feeding, last: .now.addingTimeInterval(-2 * 3600),
                            detail: "Formula · Bottle · 20m", todayCount: 4),
        sleep: KindStatus(kind: .sleep, last: .now.addingTimeInterval(-45 * 60),
                          detail: "1h 10m · Nap", todayCount: 3),
        change: KindStatus(kind: .change, last: .now.addingTimeInterval(-35 * 60),
                           detail: "Wet", todayCount: 6))
}

// MARK: - Views

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private var status: ChildStatus { entry.status }
    private let homeURL = URL(string: "babybuddy://home")

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .systemMedium: medium
        default: small
        }
    }

    // MARK: Home Screen — small

    /// Compact layout: the relative time sits under the label, with today's count on the right,
    /// so a narrow tile never has to fit a label and a long "1 day, 20 hr" on one line.
    @ViewBuilder private var small: some View {
        if status.hasChild {
            VStack(alignment: .leading, spacing: 9) {
                childHeading(size: 14)
                VStack(spacing: 9) {
                    ForEach(status.all, id: \.kind) { smallRow($0) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(homeURL)
        } else {
            noChild.widgetURL(homeURL)
        }
    }

    private func smallRow(_ s: KindStatus) -> some View {
        HStack(spacing: 8) {
            glyph(s, side: 24, icon: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.shortLabel).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                relative(s).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(s.todayCount)").font(.system(size: 14, weight: .semibold)).monospacedDigit()
                Text("today").font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Home Screen — medium

    /// Wide layout: label (+ detail) on the left, then fixed-width right-aligned LAST and TODAY
    /// columns so the times and counts line up across all three rows.
    @ViewBuilder private var medium: some View {
        if status.hasChild {
            VStack(alignment: .leading, spacing: 8) {
                childHeading(size: 15)
                VStack(spacing: 8) {
                    mediumHeaderRow
                    ForEach(status.all, id: \.kind) { mediumRow($0) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(homeURL)
        } else {
            noChild.widgetURL(homeURL)
        }
    }

    /// Column widths shared by the medium header and rows so everything aligns.
    private let lastColumn: CGFloat = 96
    private let todayColumn: CGFloat = 48

    private var mediumHeaderRow: some View {
        HStack(spacing: 10) {
            Spacer().frame(width: 26)               // under the glyph
            Spacer(minLength: 0)                     // under the flexible label column
            Text("LAST").frame(width: lastColumn, alignment: .trailing)
            Text("TODAY").frame(width: todayColumn, alignment: .trailing)
        }
        .font(.system(size: 9, weight: .semibold))
        .kerning(0.3)
        .foregroundStyle(.secondary)
    }

    private func mediumRow(_ s: KindStatus) -> some View {
        HStack(spacing: 10) {
            glyph(s, side: 26, icon: 13)
            VStack(alignment: .leading, spacing: 1) {
                Text(s.shortLabel).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                if let detail = s.detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            relative(s)
                .font(.system(size: 13, weight: .medium)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: lastColumn, alignment: .trailing)
            Text("\(s.todayCount)")
                .font(.system(size: 14, weight: .semibold)).monospacedDigit()
                .frame(width: todayColumn, alignment: .trailing)
        }
    }

    // MARK: Shared pieces

    private func childHeading(size: CGFloat) -> some View {
        Text(status.childName ?? "Baby Buddy")
            .font(.system(size: size, weight: .semibold))
            .lineLimit(1)
    }

    private func glyph(_ s: KindStatus, side: CGFloat, icon: CGFloat) -> some View {
        let tint = BBColor.activity(s.kind)
        return Image(systemName: s.kind.systemImage)
            .font(.system(size: icon, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: side * 0.28))
    }

    /// The kind's relative "last" time, self-updating via `Text(_, style: .relative)`, or "—".
    @ViewBuilder private func relative(_ s: KindStatus) -> some View {
        if let last = s.last {
            Text(last, style: .relative)
        } else {
            Text("—")
        }
    }

    private var noChild: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 22)).foregroundStyle(BBColor.brand)
            Text("Open Baby Buddy")
                .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
            Text("to pick a child").font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Lock Screen / StandBy accessories (tap-to-open only)

    /// One glanceable line — the most recent of the tracked kinds, e.g. "Fed 2h ago".
    private var inline: some View {
        let recent = mostRecent
        return Label {
            if let recent, let last = recent.last {
                Text("\(recent.shortLabel) ") + Text(last, style: .relative)
            } else {
                Text("No activity yet")
            }
        } icon: {
            Image(systemName: (recent ?? status.feeding).kind.systemImage)
        }
    }

    private var circular: some View {
        let feeding = status.feeding
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Image(systemName: EntityKind.feeding.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                if let last = feeding.last {
                    Text(last, style: .relative)
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5).lineLimit(1)
                } else {
                    Text("—").font(.system(size: 11, weight: .medium))
                }
            }
            .padding(3)
        }
        .widgetURL(homeURL)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(status.all, id: \.kind) { kind in
                HStack(spacing: 4) {
                    Image(systemName: kind.kind.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .widgetAccentable()
                        .frame(width: 14)
                    if let last = kind.last {
                        Text(last, style: .relative).font(.system(size: 12)).monospacedDigit()
                    } else {
                        Text("—").font(.system(size: 12))
                    }
                    Spacer(minLength: 2)
                    Text("\(kind.todayCount)")
                        .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(homeURL)
    }

    /// The most recently occurring tracked kind (for the single-line inline accessory).
    private var mostRecent: KindStatus? {
        status.all.filter { $0.last != nil }.max { ($0.last ?? .distantPast) < ($1.last ?? .distantPast) }
    }
}

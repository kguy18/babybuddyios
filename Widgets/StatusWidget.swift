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
                           detail: "Wet", todayCount: 6),
        runningTimer: nil)
}

// MARK: - Views

struct StatusWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: StatusEntry

    private var status: ChildStatus { entry.status }
    private let homeURL = URL(string: "babybuddy://home")

    /// Deep link to a kind's day timeline (matches the in-app "Today" tile).
    private func dayURL(_ kind: EntityKind) -> URL {
        URL(string: "babybuddy://day/\(kind.rawValue)")!
    }

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
            VStack(alignment: .leading, spacing: 6) {
                smallHeader
                VStack(spacing: 9) {
                    ForEach(status.all, id: \.kind) { smallRow($0) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .widgetURL(homeURL)
        } else {
            noChild.widgetURL(homeURL)
        }
    }

    /// Small header: the child's name, or a condensed running-timer line — name on the left,
    /// elapsed and the running dot right-aligned.
    @ViewBuilder private var smallHeader: some View {
        if let timer = status.runningTimer {
            HStack(spacing: 5) {
                Text(timer.name).font(.system(size: 13, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 2)
                Text(timer.start, style: .timer)
                    .font(.system(size: 12, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(BBColor.success)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 48, alignment: .trailing)
                runningDot(diameter: 11, dot: 6)
            }
        } else {
            Text(status.childName ?? "Baby Buddy")
                .font(.system(size: 14, weight: .semibold)).lineLimit(1)
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

    /// Colour-tile layout: a header (child name, or the running-timer line) over three tinted
    /// activity tiles, each with a solid glyph chip, its "last" age, and today's count.
    @ViewBuilder private var medium: some View {
        if status.hasChild {
            VStack(alignment: .leading, spacing: 8) {
                mediumHeader
                HStack(spacing: 10) {
                    ForEach(status.all, id: \.kind) { s in
                        // Each tile opens that kind's day timeline — same as the in-app "Today"
                        // tile. (Links work in medium/large widgets; small uses widgetURL.)
                        Link(destination: dayURL(s.kind)) { colourTile(s) }
                    }
                }
                .frame(maxHeight: .infinity)   // tiles flex to fill the height below the header
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .widgetURL(homeURL)
        } else {
            noChild.widgetURL(homeURL)
        }
    }

    /// Medium header: the child's name on the left; when a timer is running, the timer name and
    /// its live counting-up elapsed time are right-aligned, with a green running dot. The elapsed
    /// text gets an explicit fixed-width frame — `Text(style: .timer)` reports a greedy width that
    /// otherwise squeezes the names out (or, with `.fixedSize`, blanks the widget entirely).
    @ViewBuilder private var mediumHeader: some View {
        if let timer = status.runningTimer {
            HStack(spacing: 6) {
                Text(status.childName ?? "Baby Buddy")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
                Spacer(minLength: 6)
                Text(timer.name)
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(timer.start, style: .timer)
                    .font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(BBColor.success)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .frame(width: 58, alignment: .trailing)
                runningDot(diameter: 13, dot: 7)
            }
        } else {
            Text(status.childName ?? "Baby Buddy")
                .font(.system(size: 15, weight: .semibold)).lineLimit(1)
        }
    }

    private func colourTile(_ s: KindStatus) -> some View {
        let tint = BBColor.activity(s.kind)
        return VStack(alignment: .leading, spacing: 2) {
            Image(systemName: s.kind.systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(tint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Spacer(minLength: 6)
            Text(tileLabel(s.kind))
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(tint).lineLimit(1)
            Text(lastAge(s))
                .font(.system(size: 18, weight: .semibold)).foregroundStyle(.primary)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text("\(s.todayCount) today")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(11)
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
    }

    // MARK: Shared pieces

    /// Short tile caption per kind ("Feeding", "Sleep", "Diaper").
    private func tileLabel(_ kind: EntityKind) -> String {
        switch kind {
        case .feeding: return "Feeding"
        case .sleep: return "Sleep"
        case .change: return "Diaper"
        default: return kind.displayName
        }
    }

    /// A green running dot with a faint halo — matches the app's `RunningDot`.
    private func runningDot(diameter: CGFloat, dot: CGFloat) -> some View {
        ZStack {
            Circle().fill(BBColor.success.opacity(0.25)).frame(width: diameter, height: diameter)
            Circle().fill(BBColor.success).frame(width: dot, height: dot)
        }
    }

    /// Compact "last" age for a tile ("20m", "2h", "1d 20h"), relative to the entry time, or "—".
    private func lastAge(_ s: KindStatus) -> String {
        guard let last = s.last else { return "—" }
        return ChildStatus.compactAge(from: last, to: entry.date)
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

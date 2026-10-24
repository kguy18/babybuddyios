import WidgetKit
import SwiftUI
import AppIntents
import SwiftData

/// Home-screen widget: a 2×2 grid of activity tiles that each start a Baby Buddy timer with
/// one tap, via ``StartTimerIntent``. An activity with a running timer for the selected child
/// shows a stopwatch and a green dot, and a tap opens that timer instead.
struct QuickStartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BabyBuddyQuickStart", provider: QuickStartProvider()) { entry in
            QuickStartView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Quick start timer")
        .description("Start a feeding, sleep, tummy time, or pumping timer.")
        .supportedFamilies([.systemSmall])
    }
}

struct QuickStartEntry: TimelineEntry {
    let date: Date
    /// The selected child's running activities, each with the local ID of the timer a tap opens.
    var runningTimers: [TimerActivity: UUID] = [:]
    /// The selected child's first name, set only when there are several children to tell apart.
    var childName: String?
}

struct QuickStartProvider: TimelineProvider {
    private func currentEntry() -> QuickStartEntry {
        guard let container = try? ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: LocalStore.storeURL))
        else { return QuickStartEntry(date: .now) }
        let context = ModelContext(container)
        let childID = SharedDefaults.selectedChildID
        let timers = (try? context.fetch(FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == "timer" }))) ?? []
        let children = ((try? context.fetch(FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == "child" }))) ?? []).filter { $0.syncState != .pendingDelete }
        let child = children.count > 1 ? children.first { $0.serverID == childID } : nil
        return QuickStartEntry(date: .now,
                               runningTimers: TimerActivity.runningActivities(in: timers, childID: childID),
                               childName: child.map(ChildStatus.firstName))
    }

    func placeholder(in context: Context) -> QuickStartEntry { QuickStartEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (QuickStartEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStartEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .never))
    }
}

struct QuickStartView: View {
    let entry: QuickStartEntry

    var body: some View {
        grid
    }

    private var grid: some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                Text(entry.childName.map { "Start a timer · \($0)" } ?? "Start a timer")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "stopwatch")
                    .font(.system(size: 12))
                    .foregroundStyle(BBColor.brand)
            }
            Grid(horizontalSpacing: 7, verticalSpacing: 7) {
                GridRow { tile(.feeding); tile(.sleep) }
                GridRow { tile(.tummyTime); tile(.pumping) }
            }
        }
    }

    /// A running tile opens its timer in the app instead of starting a duplicate. It's an intent
    /// button rather than a `Link`, which a small widget ignores.
    @ViewBuilder private func tile(_ activity: TimerActivity) -> some View {
        if let id = entry.runningTimers[activity] {
            Button(intent: OpenTimerIntent(timerLocalID: id)) { tileLabel(activity, running: true) }
                .buttonStyle(.plain)
                .accessibilityLabel("\(activity.timerName), timer running, open timer")
        } else {
            Button(intent: StartTimerIntent(activity: activity)) { tileLabel(activity, running: false) }
                .buttonStyle(.plain)
                .accessibilityLabel("\(activity.timerName), start timer")
        }
    }

    private func tileLabel(_ activity: TimerActivity, running: Bool) -> some View {
        let tint = BBColor.tint(for: activity)
        return VStack(alignment: .leading, spacing: 0) {
            Image(systemName: running ? "stopwatch" : activity.systemImage)
                .font(.system(size: 17, weight: .semibold))
            Spacer(minLength: 2)
            Text(activity.timerName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(8)
        .overlay(alignment: .topTrailing) {
            if running { WidgetRunningDot(diameter: 11, dot: 6).padding(6) }
        }
        .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
        .foregroundStyle(tint)
    }
}

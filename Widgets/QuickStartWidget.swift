import WidgetKit
import SwiftUI
import AppIntents
import SwiftData

/// Home-screen widget: a 2×2 grid of activity tiles that each start a Baby Buddy timer with
/// one tap, via ``StartTimerIntent``. Running activities show a stopwatch after the
/// shared store changes and WidgetKit reloads the timeline.
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
    var runningActivities: Set<TimerActivity> = []
}

struct QuickStartProvider: TimelineProvider {
    private func currentEntry() -> QuickStartEntry {
        guard let container = try? ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: LocalStore.storeURL))
        else { return QuickStartEntry(date: .now) }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == "timer" })
        let timers = (try? context.fetch(descriptor)) ?? []
        return QuickStartEntry(date: .now, runningActivities: TimerActivity.runningActivities(in: timers))
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
                Text("Start a timer")
                    .font(.system(size: 12, weight: .medium))
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

    private func tile(_ activity: TimerActivity) -> some View {
        let tint = BBColor.tint(for: activity)
        return Button(intent: StartTimerIntent(activity: activity)) {
            VStack(alignment: .leading, spacing: 0) {
                Image(systemName: entry.runningActivities.contains(activity) ? "stopwatch" : activity.systemImage)
                    .font(.system(size: 17, weight: .semibold))
                Spacer(minLength: 2)
                Text(activity.timerName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(8)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(activity.timerName), \(entry.runningActivities.contains(activity) ? "timer running" : "start timer")")
    }
}

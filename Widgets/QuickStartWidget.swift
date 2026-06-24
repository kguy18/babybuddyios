import WidgetKit
import SwiftUI
import AppIntents

/// Home-screen widget: a 2×2 grid of activity tiles that each start a Baby Buddy timer with
/// one tap, via ``StartTimerIntent``. Static content — it looks the same whether or not a
/// timer is running, so it's always useful.
struct QuickStartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BabyBuddyQuickStart", provider: QuickStartProvider()) { _ in
            QuickStartView()
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Quick start timer")
        .description("Start a feeding, sleep, tummy time, or pumping timer.")
        .supportedFamilies([.systemSmall])
    }
}

struct QuickStartEntry: TimelineEntry {
    let date: Date
}

struct QuickStartProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStartEntry { QuickStartEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (QuickStartEntry) -> Void) {
        completion(QuickStartEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStartEntry>) -> Void) {
        completion(Timeline(entries: [QuickStartEntry(date: .now)], policy: .never))
    }
}

struct QuickStartView: View {
    var body: some View {
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
                Image(systemName: activity.systemImage)
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
    }
}

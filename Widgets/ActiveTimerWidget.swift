import WidgetKit
import SwiftUI
import SwiftData
import AppIntents

/// The most-recent running timer with live-ticking elapsed time. On the Home screen it offers a
/// one-tap Stop button and tap-to-open actions; the Lock Screen / StandBy accessories are
/// glanceable and tap-to-open only (accessory widgets can't host interactive buttons).
struct ActiveTimerWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BabyBuddyActiveTimer", provider: ActiveTimerProvider()) { entry in
            ActiveTimerView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Active timer")
        .description("See your running timer at a glance and stop it with one tap.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

/// Plain snapshot of a running timer, decoupled from SwiftData so it can live in a TimelineEntry.
/// `activity` is resolved at capture time (hint-first, name-fallback) so a custom-named timer
/// still shows the right icon and routes Stop to the right activity.
struct TimerSnapshot {
    let localID: String
    let name: String
    let start: Date
    let activity: TimerActivity?
}

struct ActiveTimerEntry: TimelineEntry {
    let date: Date
    let timer: TimerSnapshot?
    let isPremium: Bool
}

struct ActiveTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> ActiveTimerEntry {
        ActiveTimerEntry(date: .now, timer: TimerSnapshot(
            localID: "", name: "Sleep", start: .now.addingTimeInterval(-3725), activity: .sleep),
            isPremium: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ActiveTimerEntry) -> Void) {
        completion(ActiveTimerEntry(date: .now, timer: Self.currentTimer(),
                                    isPremium: context.isPreview || SharedDefaults.isPremium))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ActiveTimerEntry>) -> Void) {
        // Elapsed time renders via `Text(_, style: .timer)`, so no periodic reloads are needed;
        // the start/stop intents and the app explicitly reload when a timer changes.
        completion(Timeline(entries: [ActiveTimerEntry(date: .now, timer: Self.currentTimer(),
                                                       isPremium: SharedDefaults.isPremium)],
                            policy: .never))
    }

    /// The most-recent running timer in the shared store, or `nil` if none is running.
    static func currentTimer() -> TimerSnapshot? {
        guard let container = try? ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: LocalStore.storeURL))
        else { return nil }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == "timer" },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        guard let timers = try? context.fetch(descriptor),
              let timer = timers.first(where: { $0.syncState != .pendingDelete })
        else { return nil }
        let name = (timer.payloadObject["name"] as? String) ?? "Timer"
        return TimerSnapshot(localID: timer.localID.uuidString, name: name, start: timer.timestamp,
                             activity: TimerActivity(timer: timer))
    }
}

struct ActiveTimerView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ActiveTimerEntry

    var body: some View {
        switch family {
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        case .accessoryInline: inline
        default:
            // Home Screen widget is a premium feature; Lock Screen accessories stay as free glances.
            if !entry.isPremium { WidgetLockedView() }
            else if let timer = entry.timer { running(timer) } else { empty }
        }
    }

    // MARK: Lock Screen / StandBy accessories (tap-to-open; no interactive buttons)

    @ViewBuilder private var rectangular: some View {
        if let timer = entry.timer {
            VStack(alignment: .leading, spacing: 2) {
                Label(timer.name, systemImage: timer.activity?.systemImage ?? "timer")
                    .font(.headline)
                    .widgetAccentable()
                Text(timer.start, style: .timer)
                    .font(.title2)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(timerURL(timer))
        } else {
            Label("No timer running", systemImage: "timer")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .widgetURL(homeURL)
        }
    }

    @ViewBuilder private var circular: some View {
        if let timer = entry.timer {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: timer.activity?.systemImage ?? "timer")
                        .font(.system(size: 14, weight: .semibold))
                    Text(timer.start, style: .timer)
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                }
                .padding(4)
            }
            .widgetURL(timerURL(timer))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "timer").font(.system(size: 18))
            }
            .widgetURL(homeURL)
        }
    }

    @ViewBuilder private var inline: some View {
        if let timer = entry.timer {
            // Inline must stay one line; the icon conveys the activity and the elapsed keeps ticking.
            Label {
                Text(timer.start, style: .timer)
            } icon: {
                Image(systemName: timer.activity?.systemImage ?? "timer")
            }
        } else {
            Label("No timer", systemImage: "timer")
        }
    }

    private func timerURL(_ timer: TimerSnapshot) -> URL? {
        URL(string: "babybuddy://timer/\(timer.localID)")
    }
    private var homeURL: URL? { URL(string: "babybuddy://home") }

    private func running(_ timer: TimerSnapshot) -> some View {
        let tint = timer.activity.map(BBColor.tint(for:)) ?? BBColor.brand
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: timer.activity?.systemImage ?? "timer")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                Text(timer.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "circle.fill")
                    .font(.system(size: 7))
                    .foregroundStyle(BBColor.feeding)
            }
            Spacer(minLength: 4)
            Text(timer.start, style: .timer)
                .font(.system(size: 30, weight: .medium, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Spacer(minLength: 6)
            stopControl(timer)
        }
        .widgetURL(URL(string: "babybuddy://timer/\(timer.localID)"))
    }

    /// Stop logs the activity. Sleep/tummy time record in one tap (background intent);
    /// feeding/pumping need extra fields, so they open a pre-filled in-app form via a deep
    /// link; an unrecognized timer name opens the generic timer actions.
    @ViewBuilder private func stopControl(_ timer: TimerSnapshot) -> some View {
        let route = TimerStopRoute.resolve(localID: timer.localID, activity: timer.activity)
        switch route {
        case .log(let id):
            Button(intent: LogTimerIntent(timerLocalID: id)) { stopLabel }
                .buttonStyle(.plain)
        case .convertForm, .openActions:
            Link(destination: route.deepLink!) { stopLabel }
        }
    }

    private var stopLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: "stop.fill").font(.system(size: 11))
            Text("Stop").font(.system(size: 13, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(BBColor.stop, in: RoundedRectangle(cornerRadius: 9))
        .foregroundStyle(Color(red: 0x5A / 255.0, green: 0x43 / 255.0, blue: 0x02 / 255.0))
    }

    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "timer")
                .font(.system(size: 22))
                .foregroundStyle(BBColor.brand)
            Text("No timer running")
                .font(.system(size: 13, weight: .medium))
                .multilineTextAlignment(.center)
            Text("Tap to start one")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "babybuddy://home"))
    }
}

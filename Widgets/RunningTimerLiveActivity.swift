import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Live Activity for a running timer: a Lock Screen banner and the Dynamic Island. Mirrors the
/// Active Timer widget's content (icon + name + self-ticking elapsed via `Text(_, style: .timer)`,
/// per-activity tint) and its Stop behavior (``TimerStopRoute``): sleep/tummy log in one tap;
/// feeding/pumping open the convert form; an uncategorized timer opens its generic actions.
/// Tapping the body opens the app to that timer (`babybuddy://timer/<localID>`).
///
/// Hosted by the widget extension. The app owns the activity's lifecycle (see
/// `LiveActivityManager`); the widget-extension intents can't start/stop it, so the Stop button's
/// `LogTimerIntent` logs the timer and the banner clears on the app's next foreground reconcile.
struct RunningTimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunningTimerAttributes.self) { context in
            lockScreen(context)
        } dynamicIsland: { context in
            let tint = context.state.activity.map(BBColor.tint(for:)) ?? BBColor.brand
            let icon = context.state.activity?.systemImage ?? "timer"
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.state.title).lineLimit(1)
                    } icon: {
                        Image(systemName: icon).foregroundStyle(tint)
                    }
                    .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(BBColor.success)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.start, style: .timer)
                        .font(.system(size: 34, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: .infinity)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    stopControl(context)
                }
            } compactLeading: {
                Image(systemName: icon).foregroundStyle(tint)
            } compactTrailing: {
                Text(context.state.start, style: .timer)
                    .monospacedDigit()
                    .foregroundStyle(tint)
                    .frame(maxWidth: 44)
            } minimal: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            .widgetURL(bodyURL(context))
            .keylineTint(tint)
        }
    }

    // MARK: Lock Screen / banner

    @ViewBuilder
    private func lockScreen(_ context: ActivityViewContext<RunningTimerAttributes>) -> some View {
        let tint = context.state.activity.map(BBColor.tint(for:)) ?? BBColor.brand
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: context.state.activity?.systemImage ?? "timer")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(context.state.title)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                }
                Text(context.state.start, style: .timer)
                    .font(.system(size: 34, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            stopControl(context).frame(width: 92)
        }
        .padding(16)
        .widgetURL(bodyURL(context))
    }

    // MARK: Stop control (mirrors ActiveTimerWidget)

    @ViewBuilder
    private func stopControl(_ context: ActivityViewContext<RunningTimerAttributes>) -> some View {
        let route = TimerStopRoute.resolve(localID: context.attributes.timerLocalID,
                                           activity: context.state.activity)
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
        .padding(.vertical, 8)
        .background(BBColor.stop, in: RoundedRectangle(cornerRadius: 9))
        .foregroundStyle(Color(red: 0x5A / 255.0, green: 0x43 / 255.0, blue: 0x02 / 255.0))
    }

    private func bodyURL(_ context: ActivityViewContext<RunningTimerAttributes>) -> URL? {
        URL(string: "babybuddy://timer/\(context.attributes.timerLocalID)")
    }
}

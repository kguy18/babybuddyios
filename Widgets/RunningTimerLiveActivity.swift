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
/// `LiveActivityManager`). The Stop button's `LogTimerIntent` is a `LiveActivityIntent`, so it
/// runs in the app's process and ends this banner itself the moment Stop is tapped. The
/// convert-form / open-actions Stop routes instead open the app, which clears the banner on its
/// next foreground reconcile.
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
        let stop = stopControl(context, font: .footnote.weight(.medium))
            .frame(minWidth: 92)
            .fixedSize(horizontal: true, vertical: false)

        HStack(spacing: 0) {
            Rectangle()
                .fill(tint)
                .frame(width: 4)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 11) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tint.opacity(0.2))
                        .frame(width: 38, height: 38)
                        .overlay {
                            Image(systemName: context.state.activity?.systemImage ?? "timer")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(tint)
                        }
                    VStack(alignment: .leading, spacing: 2) {
                        timerTitle(context.state.title).fixedSize()
                        elapsed(context.state.start)
                    }
                    Spacer(minLength: 0)
                    stop
                }

                VStack(alignment: .leading, spacing: 2) {
                    timerTitle(context.state.title).minimumScaleFactor(0.6)
                    HStack(spacing: 11) {
                        elapsed(context.state.start)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        stop
                    }
                }
            }
            .padding(14)
        }
        .widgetURL(bodyURL(context))
    }

    private func timerTitle(_ title: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .lineLimit(1)
            Circle().fill(BBColor.success).frame(width: 7, height: 7)
        }
    }

    private func elapsed(_ start: Date) -> some View {
        Text(start, style: .timer)
            .font(.system(.title, design: .rounded).weight(.medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    // MARK: Stop control (mirrors ActiveTimerWidget)

    @ViewBuilder
    private func stopControl(
        _ context: ActivityViewContext<RunningTimerAttributes>,
        font: Font = .system(size: 13, weight: .medium)
    ) -> some View {
        let route = TimerStopRoute.resolve(localID: context.attributes.timerLocalID,
                                           activity: context.state.activity)
        switch route {
        case .log(let id):
            Button(intent: LogTimerIntent(timerLocalID: id)) { stopLabel(font: font) }
                .buttonStyle(.plain)
        case .convertForm, .openActions:
            Link(destination: route.deepLink!) { stopLabel(font: font) }
        }
    }

    private func stopLabel(font: Font) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "stop.fill").font(.system(size: 11))
            Text("Stop").font(font)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(BBColor.stop, in: RoundedRectangle(cornerRadius: 9))
        .foregroundStyle(Color(red: 0x5A / 255.0, green: 0x43 / 255.0, blue: 0x02 / 255.0))
    }

    private func bodyURL(_ context: ActivityViewContext<RunningTimerAttributes>) -> URL? {
        URL(string: "babybuddy://timer/\(context.attributes.timerLocalID)")
    }
}

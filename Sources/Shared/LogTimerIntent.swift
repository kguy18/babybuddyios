import ActivityKit
import AppIntents
import SwiftData
import WidgetKit

/// Stops a running timer by logging it as a completed activity — start = the timer's start,
/// end = now — and removing the timer, reusing `LocalRepository.convertTimer`. Used by the
/// Active Timer widget's Stop button for activities that need no extra fields (sleep, tummy
/// time). Feeding/pumping require type/method/amount, so the widget routes those to the
/// in-app form instead. The created activity is pushed to the server immediately (best-effort
/// via ``TimerPush``); on failure it stays queued for the app's next sync.
///
/// Conforms to ``LiveActivityIntent`` so the system runs `perform()` in the **app's** process
/// (foreground or a background launch) rather than the widget extension. That's what lets the
/// same Stop button on the running-timer Live Activity end its Lock Screen / Dynamic Island
/// banner immediately — the widget-extension process can't touch the app-owned activity, so
/// without this the banner would linger until the app's next foreground reconcile.
struct LogTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop and log timer"
    static var description = IntentDescription("Stops a running timer and records it as a completed activity.")

    @Parameter(title: "Timer")
    var timerLocalID: String

    init() {}
    init(timerLocalID: String) { self.timerLocalID = timerLocalID }

    @MainActor
    func perform() async throws -> some IntentResult {
        // May run in a fresh background launch of the app process, so start analytics defensively.
        Analytics.start()
        guard SharedDefaults.isPremium else {
            Analytics.widgetIntent("LogTimerBlocked")
            throw PremiumRequiredError()
        }
        Analytics.widgetIntent("LogTimer")
        let container = try ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: LocalStore.storeURL))
        let context = container.mainContext

        if let id = UUID(uuidString: timerLocalID),
           let timer = LocalStore.fetch(localID: id, in: context),
           let activity = TimerActivity(timer: timer),
           activity.isInstantLoggable {
            let start = (timer.payloadObject["start"] as? String)
                ?? APIDate.isoDateTime.string(from: timer.timestamp)
            var payload: [String: Any] = [
                "start": start,
                "end": APIDate.isoDateTime.string(from: .now),
            ]
            if let child = timer.childID { payload["child"] = child }
            let logged = LocalRepository(context: context).convertTimer(
                timer, to: activity.convertKind, payload: payload)
            Analytics.timerStopped(activity: activity.rawValue, source: .widget)
            if let logged { await TimerPush.pushCreate(localID: logged.localID, in: context) }
        }
        // Running in the app's process (via `LiveActivityIntent`), so end the timer's Live Activity
        // right here — the Lock Screen / Dynamic Island banner clears the instant Stop is tapped
        // instead of waiting for the app's next foreground reconcile.
        await endLiveActivity(timerLocalID: timerLocalID)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }

    /// End any running-timer Live Activity for `timerLocalID`. No-op when none exists (e.g. the
    /// Stop came from the Home-screen widget with Live Activities off) or when this runs in the
    /// widget-extension copy of the type, where `activities` is empty.
    @MainActor
    private func endLiveActivity(timerLocalID: String) async {
        for activity in Activity<RunningTimerAttributes>.activities
        where activity.attributes.timerLocalID == timerLocalID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}

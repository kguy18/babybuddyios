import AppIntents
import SwiftData
import WidgetKit

/// Starts a Baby Buddy timer for an activity. Invoked by the Quick Start widget's buttons
/// (and available to Siri/Shortcuts). Writes to the App Group store via ``LocalRepository`` and
/// then pushes the create to the server immediately (best-effort via ``TimerPush``); if that
/// fails (offline, not signed in) the mutation stays queued for the app's next sync.
struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a timer"
    static var description = IntentDescription("Starts a Baby Buddy timer for an activity.")

    @Parameter(title: "Activity")
    var activity: TimerActivity

    init() {}
    init(activity: TimerActivity) { self.activity = activity }

    @MainActor
    func perform() async throws -> some IntentResult {
        // The intent runs in a separate process from the app, so analytics must be started here.
        Analytics.start()
        // Home Screen widgets / timer intents are a premium feature. Free users are blocked here too
        // (not just in the widget UI) so Siri / Shortcuts can't bypass the gate.
        guard SharedDefaults.isPremium else {
            Analytics.widgetIntent("StartTimerBlocked")
            throw PremiumRequiredError()
        }
        Analytics.widgetIntent("StartTimer")
        let container = try ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: LocalStore.storeURL))

        var payload: [String: Any] = [
            // Set start locally so elapsed time is correct immediately and survives the round
            // trip; the server accepts a provided start.
            "start": APIDate.isoDateTime.string(from: .now),
            "name": activity.timerName,
        ]
        if let child = SharedDefaults.selectedChildID, child > 0 {
            payload["child"] = child
        }

        let context = container.mainContext
        let timer = LocalRepository(context: context).create(
            kind: .timer, payload: payload, timerActivity: activity.convertKind)
        Analytics.timerStarted(activity: activity.rawValue, source: .widget)
        if let timer { await TimerPush.pushCreate(localID: timer.localID, in: context) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

/// Thrown by the widget timer intents when the customer isn't premium — the system surfaces the
/// message. The widget UI already shows a locked state; this covers Siri / Shortcuts invocations.
struct PremiumRequiredError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Baby Buddy Pro is required to use timer widgets."
    }
}

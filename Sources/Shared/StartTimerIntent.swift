import AppIntents
import SwiftData
import WidgetKit

/// Starts a Baby Buddy timer for an activity. Invoked by the Quick Start widget's buttons
/// (and available to Siri/Shortcuts). Local-only model: it writes to the App Group store and
/// enqueues a `PendingMutation` via ``LocalRepository``; the server is updated on the app's
/// next foreground or background sync.
struct StartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a timer"
    static var description = IntentDescription("Starts a Baby Buddy timer for an activity.")

    @Parameter(title: "Activity")
    var activity: TimerActivity

    init() {}
    init(activity: TimerActivity) { self.activity = activity }

    @MainActor
    func perform() async throws -> some IntentResult {
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

        LocalRepository(context: container.mainContext).create(kind: .timer, payload: payload)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

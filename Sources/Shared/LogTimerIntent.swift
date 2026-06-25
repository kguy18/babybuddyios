import AppIntents
import SwiftData
import WidgetKit

/// Stops a running timer by logging it as a completed activity — start = the timer's start,
/// end = now — and removing the timer, reusing `LocalRepository.convertTimer`. Used by the
/// Active Timer widget's Stop button for activities that need no extra fields (sleep, tummy
/// time). Feeding/pumping require type/method/amount, so the widget routes those to the
/// in-app form instead. The created activity is pushed to the server immediately (best-effort
/// via ``TimerPush``); on failure it stays queued for the app's next sync.
struct LogTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop and log timer"
    static var description = IntentDescription("Stops a running timer and records it as a completed activity.")

    @Parameter(title: "Timer")
    var timerLocalID: String

    init() {}
    init(timerLocalID: String) { self.timerLocalID = timerLocalID }

    @MainActor
    func perform() async throws -> some IntentResult {
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
            if let logged { await TimerPush.pushCreate(localID: logged.localID, in: context) }
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

import AppIntents
import SwiftData
import WidgetKit

/// Stops (deletes) a running Baby Buddy timer, identified by its local id. Invoked by the
/// Active Timer widget's Stop button. Goes through the same `LocalRepository.delete` path as
/// the in-app "Stop Timer" action — base-snapshot conflict checking included — and enqueues a
/// `PendingMutation` for the next sync.
struct StopTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop timer"
    static var description = IntentDescription("Stops a running Baby Buddy timer.")

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
           let timer = LocalStore.fetch(localID: id, in: context) {
            LocalRepository(context: context).delete(timer)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

import AppIntents
import SwiftData
import WidgetKit

/// Logs a complete diaper change (Wet / Solid / Wet + Solid) in a single tap — no timer, no
/// form. Invoked by the Quick Log widget's buttons (and available to Siri/Shortcuts). Writes to
/// the App Group store via ``LocalRepository`` and then pushes the create to the server
/// immediately (best-effort via ``TimerPush``); if that fails (offline, not signed in) the
/// mutation stays queued for the app's next sync. Unlike a timer, a change REQUIRES a child, so
/// the intent fails cleanly when none is selected rather than posting an invalid record.
struct QuickLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Log a diaper change"
    static var description = IntentDescription("Logs a complete diaper change in one tap.")

    @Parameter(title: "Action")
    var action: QuickLogAction

    init() {}
    init(action: QuickLogAction) { self.action = action }

    @MainActor
    func perform() async throws -> some IntentResult {
        // The intent runs in a separate process from the app, so analytics must be started here.
        // An intent run isn't a session, so it doesn't send `TelemetryDeck.Session.started`.
        Analytics.start(sendSessionStarted: false)
        // A diaper change requires a child; fail cleanly rather than posting an invalid record.
        guard let child = SharedDefaults.selectedChildID, child > 0 else {
            throw NoChildSelectedError()
        }
        let container = try ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: LocalStore.storeURL))
        let context = container.mainContext

        // create() already fires Analytics.activityLogged for non-timer kinds, so don't double-log.
        guard let entity = LocalRepository(context: context).create(
            kind: action.kind, payload: action.payload(childID: child, now: .now), source: .intent)
        else { throw QuickLogSaveError() }
        // create() is best-effort. Confirm persistence before recording a success receipt.
        do { try context.save() } catch { throw QuickLogSaveError() }
        QuickLogFeedback.record(action: action, entityID: entity.localID, childID: child, now: .now)
        await TimerPush.pushCreate(localID: entity.localID, in: context)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct QuickLogSaveError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource { "Could not save this entry. Open Baby Buddy and try again." }
}

/// Thrown by ``QuickLogIntent`` when no child is selected — a diaper change requires one, so
/// rather than posting an invalid record the intent fails and the system surfaces this message.
struct NoChildSelectedError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Open Baby Buddy and select a child first."
    }
}

import ActivityKit
import Foundation
import SwiftData

/// Keeps the running-timer Live Activity in sync with the shared App Group store.
///
/// The app owns the Live Activity lifecycle: it starts one when a timer starts in-app and ends it
/// when the timer stops or is discarded. Both are expressed through a single ``reconcile()`` step
/// that diffs the store's current running timer against the live activities, so no call site can
/// start-without-ending (or vice-versa).
///
/// `reconcile()` also runs whenever the app becomes active. That's what syncs the Live Activity up
/// after a timer is started (or a feeding/pumping timer stopped via the convert form) from the
/// **widget or Siri** — those App Intents run in the widget-extension process, where
/// `Activity.request` isn't available, so they can't start the activity themselves; the banner
/// appears on the app's next foreground. (The one-tap Stop button is the exception: its
/// `LogTimerIntent` is a `LiveActivityIntent` that runs in-app and ends its own banner directly.)
@MainActor
@Observable
final class LiveActivityManager {
    /// Reconcile the Live Activity with the shared store's most-recent running timer: end stale
    /// activities, update a changed one, and request a missing one. Safe to call repeatedly.
    func reconcile() async {
        // Respect the in-app setting and the system permission — if either is off, clear anything
        // we have and stop.
        guard SharedDefaults.liveActivitiesEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else {
            await endAll()
            return
        }

        let desired = currentRunningTimer()
        let existing = Activity<RunningTimerAttributes>.activities

        // End activities that no longer match the running timer (stopped/discarded, or replaced).
        for activity in existing where activity.attributes.timerLocalID != desired?.attributes.timerLocalID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard let desired else { return }

        if let match = existing.first(where: { $0.attributes.timerLocalID == desired.attributes.timerLocalID }) {
            // Refresh content only if the name/activity/start changed (e.g. edited in-app).
            if match.content.state != desired.state {
                await match.update(ActivityContent(state: desired.state, staleDate: nil))
            }
        } else {
            do {
                _ = try Activity.request(attributes: desired.attributes,
                                         content: ActivityContent(state: desired.state, staleDate: nil),
                                         pushType: nil)
            } catch {
                // Requesting can fail (e.g. too many activities, or the user disabled them between
                // the check above and here). Nothing actionable — the next reconcile retries.
            }
        }
    }

    private func endAll() async {
        for activity in Activity<RunningTimerAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    /// The most-recent running timer in the shared App Group store as activity attributes +
    /// content, or `nil` if none is running. Opens its own container so it reads the latest
    /// on-disk state written by either the app or the widget-extension intents (mirrors the Active
    /// Timer widget's `ActiveTimerProvider.currentTimer()`).
    private func currentRunningTimer() -> (attributes: RunningTimerAttributes,
                                           state: RunningTimerAttributes.ContentState)? {
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
        return RunningTimerAttributes.from(timer: timer,
                                           childName: childFirstName(for: timer.childID, in: context))
    }

    /// The first name of the child with `childID` in the shared store, or `nil` if unassigned or
    /// not found. Used to prefix the Live Activity header (e.g. "Patrick · Sleep").
    private func childFirstName(for childID: Int?, in context: ModelContext) -> String? {
        guard let childID else { return nil }
        let descriptor = FetchDescriptor<LocalEntity>(predicate: #Predicate { $0.kindRaw == "child" })
        guard let children = try? context.fetch(descriptor),
              let child = children.first(where: { $0.serverID == childID }) else { return nil }
        let payload = child.payloadObject
        let first = (payload["first_name"] as? String) ?? ""
        if !first.isEmpty { return first }
        let last = (payload["last_name"] as? String) ?? ""
        return last.isEmpty ? nil : last
    }
}

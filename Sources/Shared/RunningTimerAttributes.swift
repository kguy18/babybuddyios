import ActivityKit
import Foundation

/// Live Activity attributes for a running Baby Buddy timer. Shared so the app can start/end the
/// activity and the widget extension can render it. Named to avoid colliding with the existing
/// ``TimerActivity`` enum.
///
/// Elapsed time is derived from `state.start` via `Text(_, style: .timer)`, so the activity
/// self-ticks with no pushes or periodic updates — the content only changes if the timer's name,
/// activity, or start is edited (handled by the app's reconcile).
struct RunningTimerAttributes: ActivityAttributes {
    /// Stable identity of the timer this activity represents (its `LocalEntity.localID`, as a
    /// string). Used to match/end the right activity and to build the tap/Stop deep links.
    let timerLocalID: String

    struct ContentState: Codable, Hashable {
        /// Timer name shown beside the icon (e.g. "Sleep", or a custom timer name).
        var timerName: String
        /// The resolved ``TimerActivity`` raw value (hint-first, name-fallback), or `nil` for an
        /// uncategorized/custom timer. Drives the icon/tint and the Stop route.
        var activityRaw: String?
        /// The timer's start; elapsed is rendered from this and never needs pushing.
        var start: Date
        /// The child's first name (or `nil` for an unassigned timer), prefixed onto the header.
        var childName: String?

        /// The activity this timer represents, resolved from ``activityRaw``.
        var activity: TimerActivity? { activityRaw.flatMap(TimerActivity.init(rawValue:)) }

        /// Header text: "Patrick · Sleep" when the child is known, else just the timer name.
        var title: String {
            guard let childName, !childName.isEmpty else { return timerName }
            return "\(childName) · \(timerName)"
        }
    }
}

extension RunningTimerAttributes {
    /// Build the attributes + initial content for a running-timer `LocalEntity`, or `nil` if it
    /// isn't a `.timer`. Mirrors the Active Timer widget's `TimerSnapshot` capture (hint-first,
    /// name-fallback activity resolution) so both presentations agree. `childName` (resolved from
    /// the store by the caller) is prefixed onto the header — e.g. "Patrick · Sleep".
    static func from(timer: LocalEntity,
                     childName: String? = nil) -> (attributes: RunningTimerAttributes, state: ContentState)? {
        guard timer.kind == .timer else { return nil }
        let name = (timer.payloadObject["name"] as? String) ?? "Timer"
        let state = ContentState(timerName: name,
                                 activityRaw: TimerActivity(timer: timer)?.rawValue,
                                 start: timer.timestamp,
                                 childName: childName)
        return (RunningTimerAttributes(timerLocalID: timer.localID.uuidString), state)
    }
}

import Foundation
import Observation

/// Routes incoming `babybuddy://` deep links (from the widgets) into in-app navigation.
/// Views observe the published state and react — e.g. the dashboard opens a timer's actions.
@MainActor
@Observable
final class DeepLinkRouter {
    /// A timer to convert into a specific activity (the widget Stop button for feeding/pumping,
    /// which need a form). Cleared once handled.
    struct ConvertTarget: Equatable {
        let localID: UUID
        let kind: EntityKind
    }

    /// Set when a widget body, Live Activity or forgotten-timer alert is tapped: show that timer on
    /// Home. Cleared once handled.
    var openTimerLocalID: UUID?

    /// Set when Stop is tapped on a widget or Live Activity for a timer with no type: stop it and
    /// open the Stop sheet. Cleared once handled.
    var stopTimerLocalID: UUID?

    /// Set when a widget asks to convert a specific timer; cleared once handled.
    var convertTarget: ConvertTarget?

    /// Set when the status widget asks to open a kind's day timeline (a tile tap); cleared once
    /// handled.
    var openDayKind: EntityKind?

    /// Set when a Latest row on Home asks for the Timeline filtered to its kind; cleared once
    /// the Timeline has applied it.
    var showTimelineKind: EntityKind?

    /// Set by sick mode's "See all": open the Timeline tab as it is. Cleared once switched.
    var showTimeline = false

    /// Set when a medication reminder is tapped: the dose whose next dose is now OK, to log the
    /// next one from. Cleared once handled.
    var repeatDoseLocalID: UUID?

    /// Set when a link asks to present the supporter screen; cleared once handled. Nothing in the
    /// app emits `babybuddy://supporter` today, but the route stays live so an existing link still
    /// lands somewhere sensible.
    var showSupporter = false

    /// Parse a `babybuddy://` URL into router state. Returns `true` if it was recognized.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "babybuddy" else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "timer": // babybuddy://timer/<localID>
            if let id = parts.first.flatMap(UUID.init(uuidString:)) { openTimerLocalID = id }
            return true
        case "stop": // babybuddy://stop/<localID>
            if let id = parts.first.flatMap(UUID.init(uuidString:)) { stopTimerLocalID = id }
            return true
        case "convert": // babybuddy://convert/<localID>/<kindRaw>
            if parts.count >= 2, let id = UUID(uuidString: parts[0]), let kind = EntityKind(rawValue: parts[1]) {
                convertTarget = ConvertTarget(localID: id, kind: kind)
            }
            return true
        case "day": // babybuddy://day/<kindRaw> — open that kind's day timeline
            if let raw = parts.first, let kind = EntityKind(rawValue: raw) { openDayKind = kind }
            return true
        case "dose": // babybuddy://dose/<localID> — log the next dose of that medication
            if let id = parts.first.flatMap(UUID.init(uuidString:)) { repeatDoseLocalID = id }
            return true
        case "supporter": // babybuddy://supporter — present the supporter screen
            showSupporter = true
            return true
        case "home":
            return true
        default:
            return false
        }
    }
}

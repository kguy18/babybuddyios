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

    /// Set when a widget asks to open a specific timer's actions; cleared once handled.
    var openTimerLocalID: UUID?

    /// Set when a widget asks to convert a specific timer; cleared once handled.
    var convertTarget: ConvertTarget?

    /// Set when the status widget asks to open a kind's day timeline (a tile tap); cleared once
    /// handled.
    var openDayKind: EntityKind?

    /// Set when a link asks to present the paywall; cleared once handled. Nothing in the app emits
    /// `babybuddy://premium` today — the locked widgets that did are gone — but the route stays live
    /// so an existing link still lands somewhere sensible.
    var showPremium = false

    /// Parse a `babybuddy://` URL into router state. Returns `true` if it was recognized.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "babybuddy" else { return false }
        let parts = url.pathComponents.filter { $0 != "/" }
        switch url.host {
        case "timer": // babybuddy://timer/<localID>
            if let id = parts.first.flatMap(UUID.init(uuidString:)) { openTimerLocalID = id }
            return true
        case "convert": // babybuddy://convert/<localID>/<kindRaw>
            if parts.count >= 2, let id = UUID(uuidString: parts[0]), let kind = EntityKind(rawValue: parts[1]) {
                convertTarget = ConvertTarget(localID: id, kind: kind)
            }
            return true
        case "day": // babybuddy://day/<kindRaw> — open that kind's day timeline
            if let raw = parts.first, let kind = EntityKind(rawValue: raw) { openDayKind = kind }
            return true
        case "premium": // babybuddy://premium — present the paywall
            showPremium = true
            return true
        case "home":
            return true
        default:
            return false
        }
    }
}

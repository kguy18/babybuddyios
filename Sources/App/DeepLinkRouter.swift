import Foundation
import Observation

/// Routes incoming `babybuddy://` deep links (from the widgets) into in-app navigation.
/// Views observe the published state and react — e.g. the dashboard opens a timer's actions.
@MainActor
@Observable
final class DeepLinkRouter {
    /// Set when a widget asks to open a specific timer's actions; cleared once handled.
    var openTimerLocalID: UUID?

    /// Parse a `babybuddy://` URL into router state. Returns `true` if it was recognized.
    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard url.scheme == "babybuddy" else { return false }
        switch url.host {
        case "timer": // babybuddy://timer/<localID>
            let idString = url.pathComponents.first { $0 != "/" } ?? ""
            if let id = UUID(uuidString: idString) { openTimerLocalID = id }
            return true
        case "home":
            return true
        default:
            return false
        }
    }
}

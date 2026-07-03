import Foundation

/// The action a Stop control performs for a running timer — the single source of truth shared by
/// the Active Timer widget and the Live Activity so both route identically:
///
/// - sleep / tummy time (`isInstantLoggable`) → log in one tap via `LogTimerIntent`
/// - feeding / pumping → open a pre-filled convert form (needs extra fields)
/// - uncategorized / custom timer → open the generic timer actions
enum TimerStopRoute: Equatable {
    /// Instant-loggable: record via `LogTimerIntent(timerLocalID:)` in one tap (no app launch).
    case log(localID: String)
    /// Needs extra fields: open the pre-filled convert form via a `babybuddy://convert` deep link.
    case convertForm(localID: String, kind: EntityKind)
    /// Uncategorized/custom timer: open the generic actions via a `babybuddy://timer` deep link.
    case openActions(localID: String)

    /// Resolve the route for a timer's activity (or `nil` for an uncategorized timer).
    static func resolve(localID: String, activity: TimerActivity?) -> TimerStopRoute {
        guard let activity else { return .openActions(localID: localID) }
        return activity.isInstantLoggable
            ? .log(localID: localID)
            : .convertForm(localID: localID, kind: activity.convertKind)
    }

    /// The `babybuddy://` deep link the route opens, or `nil` for `.log` (which runs an in-process
    /// intent rather than launching the app).
    var deepLink: URL? {
        switch self {
        case .log:
            return nil
        case .convertForm(let id, let kind):
            return URL(string: "babybuddy://convert/\(id)/\(kind.rawValue)")
        case .openActions(let id):
            return URL(string: "babybuddy://timer/\(id)")
        }
    }
}

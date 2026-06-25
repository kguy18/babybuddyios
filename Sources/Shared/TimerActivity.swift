import AppIntents

/// The activities a quick-start timer can represent. Baby Buddy timers are generic (a child +
/// a name); the activity here sets the timer's name and the icon, and is the expected target
/// when the timer is later converted into a completed record.
enum TimerActivity: String, AppEnum, CaseIterable {
    case feeding, sleep, tummyTime, pumping

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Activity" }

    static var caseDisplayRepresentations: [TimerActivity: DisplayRepresentation] {
        [.feeding: "Feeding", .sleep: "Sleep", .tummyTime: "Tummy time", .pumping: "Pumping"]
    }

    /// Best-effort match of an existing timer's name back to an activity, for icon/tint in the
    /// Active Timer widget. Returns `nil` for custom-named timers (shown with a generic icon).
    init?(timerName: String) {
        guard let match = TimerActivity.allCases.first(where: { $0.timerName == timerName })
        else { return nil }
        self = match
    }

    /// The activity whose ``convertKind`` is `kind`, or `nil` if `kind` isn't a timer activity.
    init?(convertKind kind: EntityKind) {
        guard let match = TimerActivity.allCases.first(where: { $0.convertKind == kind })
        else { return nil }
        self = match
    }

    /// The activity a `.timer` entity represents, for icon/tint and auto-filing on Stop. Prefers
    /// the explicit kind persisted when the timer was started (`timerActivityRaw`); falls back to
    /// inferring from the timer's name (timers from the Quick Start widget are named after their
    /// activity). Returns `nil` for an uncategorized, custom-named timer.
    init?(timer: LocalEntity) {
        if let raw = timer.timerActivityRaw, let kind = EntityKind(rawValue: raw),
           let activity = TimerActivity(convertKind: kind) {
            self = activity
            return
        }
        if let name = timer.payloadObject["name"] as? String, let activity = TimerActivity(timerName: name) {
            self = activity
            return
        }
        return nil
    }

    /// The record kind this timer is expected to become when converted (drives the icon).
    var convertKind: EntityKind {
        switch self {
        case .feeding: return .feeding
        case .sleep: return .sleep
        case .tummyTime: return .tummyTime
        case .pumping: return .pumping
        }
    }

    /// Name given to the created Baby Buddy timer.
    var timerName: String {
        switch self {
        case .feeding: return "Feeding"
        case .sleep: return "Sleep"
        case .tummyTime: return "Tummy time"
        case .pumping: return "Pumping"
        }
    }

    var systemImage: String { convertKind.systemImage }

    /// Whether the activity can be logged from just child/start/end, so the Active Timer
    /// widget can record it in one tap on Stop. Feeding (needs type + method) and pumping
    /// (needs amount) require extra fields, so those open a pre-filled form instead.
    /// Verified against the live Baby Buddy API.
    var isInstantLoggable: Bool {
        switch self {
        case .sleep, .tummyTime: return true
        case .feeding, .pumping: return false
        }
    }
}

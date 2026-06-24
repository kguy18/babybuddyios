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
}

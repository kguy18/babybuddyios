import Foundation

/// The tiles under TODAY on Home (#188): which kinds show, in the order the customer chose in
/// Settings ▸ Appearance ▸ Today tiles. One setting for every child, kept in the App Group like
/// the Quick Log defaults. Sick mode's grid is fixed and ignores it.
enum TodayTiles {
    static let key = "todayTiles"

    /// Every kind a tile can show, in the order Settings lists the ones that are off.
    static let eligible: [EntityKind] = [
        .feeding, .sleep, .change, .tummyTime, .pumping, .medication, .temperature, .note,
    ]
    /// Home before anyone changed it.
    static let defaults: [EntityKind] = [.feeding, .sleep, .change, .tummyTime]

    /// The stored list is comma-separated raw values. `nil` (never set) is the default; an empty
    /// string is "no tiles". Unknown and repeated kinds are dropped.
    static func decode(_ raw: String?) -> [EntityKind] {
        guard let raw else { return defaults }
        var seen = Set<EntityKind>()
        return raw.split(separator: ",").compactMap { EntityKind(rawValue: String($0)) }
            .filter { eligible.contains($0) && seen.insert($0).inserted }
    }

    static func encode(_ kinds: [EntityKind]) -> String { kinds.map(\.rawValue).joined(separator: ",") }

    static func label(_ kind: EntityKind) -> String {
        switch kind {
        case .feeding: return "Feedings"
        case .change: return "Diapers"
        case .tummyTime: return "Tummy time"
        case .note: return "Notes"
        case .medication: return "Doses"
        case .temperature: return "Highest temp"
        default: return kind.displayName
        }
    }

    /// The tile's value from one child's records logged today.
    static func value(_ kind: EntityKind, today: [LocalEntity], unit: TemperatureUnit) -> String {
        let records = today.filter { $0.kind == kind }
        switch kind {
        case .sleep, .tummyTime:
            let total = records.reduce(0.0) { acc, e in
                let dates = e.startEndDates
                guard let start = dates.start, let end = dates.end else { return acc }
                return acc + end.timeIntervalSince(start)
            }
            return total > 0 ? EntityFormatting.formatInterval(total) : "—"
        case .pumping:
            let total = records.compactMap { $0.payloadObject["amount"] as? Double }.reduce(0, +)
            return total > 0 ? EntityFormatting.formatAmount(total) : "—"
        case .temperature:
            return SickMode.highestText(today, unit: unit)
        default:
            return "\(records.count)"
        }
    }
}

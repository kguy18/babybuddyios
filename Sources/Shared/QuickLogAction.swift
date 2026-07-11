import AppIntents
import SwiftUI

/// The one-tap actions a Quick Log widget tile can perform. Most are diaper changes — Baby
/// Buddy changes carry `wet`/`solid` booleans, and each diaper case fixes that pair so a single
/// tap logs a complete, meaningful change (always with at least one flag set: Baby Buddy's own
/// diaper form requires one, and a change with neither would be a no-op record). `quickFeed` is
/// a deliberately separate, opt-in action that logs a feeding with configurable defaults (the
/// type/method set in Settings, `start = end = now`) — since those defaults won't suit every
/// family it's both editable and surfaced as its own distinct tile rather than blended into the
/// diaper set. `kind` keeps the intent general across both record types.
enum QuickLogAction: String, AppEnum, CaseIterable {
    case wetDiaper, solidDiaper, wetAndSolidDiaper, quickFeed

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Quick Log" }

    static var caseDisplayRepresentations: [QuickLogAction: DisplayRepresentation] {
        [.wetDiaper: "Wet", .solidDiaper: "Solid", .wetAndSolidDiaper: "Wet + Solid",
         .quickFeed: "Feeding"]
    }

    /// Short label for the widget tile.
    var title: String {
        switch self {
        case .wetDiaper: return "Wet"
        case .solidDiaper: return "Solid"
        case .wetAndSolidDiaper: return "Wet + Solid"
        case .quickFeed: return "Feeding"
        }
    }

    /// The record kind this action logs — a diaper change, or a feeding for `quickFeed`. Drives
    /// the tile icon and tint, and tells the intent which collection to create in.
    var kind: EntityKind {
        switch self {
        case .wetDiaper, .solidDiaper, .wetAndSolidDiaper: return .change
        case .quickFeed: return .feeding
        }
    }

    var systemImage: String { kind.systemImage }

    /// Accent/tint for the widget tile, matching the record kind's activity color coding (warm
    /// tan for changes, green for feedings) — so the feed tile reads as distinct from the diapers.
    var tint: Color { BBColor.activity(kind) }

    /// The create payload for this action against `childID`, stamped to `now`. A record REQUIRES
    /// a child, so the caller must supply a valid id (the intent guards for one).
    ///
    /// - Diaper actions build a `changes` body (child + time + wet/solid), always ≥1 flag true.
    /// - `quickFeed` builds a `feedings` body with start = end = now (a zero-length feed) and the
    ///   type/method the customer chose in Settings (``SharedDefaults/quickFeedType`` /
    ///   ``SharedDefaults/quickFeedMethod``; default breast milk / both breasts). Baby Buddy
    ///   requires child + start + end + type + method on a feeding; amount is optional and
    ///   omitted. Raw values are constrained to `FeedingType`/`FeedingMethod`, verified against
    ///   the live Baby Buddy `Feeding` model's TYPE/METHOD choices (`validate_duration` accepts
    ///   end == start).
    func payload(childID: Int, now: Date) -> [String: Any] {
        let iso = APIDate.isoDateTime.string(from: now)
        switch self {
        case .wetDiaper:         return change(childID, iso, wet: true, solid: false)
        case .solidDiaper:       return change(childID, iso, wet: false, solid: true)
        case .wetAndSolidDiaper: return change(childID, iso, wet: true, solid: true)
        case .quickFeed:
            return [
                "child": childID, "start": iso, "end": iso,
                "type": SharedDefaults.quickFeedType.rawValue,
                "method": SharedDefaults.quickFeedMethod.rawValue,
            ]
        }
    }

    private func change(_ childID: Int, _ iso: String, wet: Bool, solid: Bool) -> [String: Any] {
        ["child": childID, "time": iso, "wet": wet, "solid": solid]
    }
}

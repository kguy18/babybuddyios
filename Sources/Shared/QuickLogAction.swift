import AppIntents
import SwiftUI

/// The one-tap diaper actions a Quick Log widget tile can perform. Baby Buddy diaper changes
/// carry `wet`/`solid` booleans; each case fixes that pair so a single tap logs a complete,
/// meaningful change with no timer and no form — always with at least one flag set (Baby
/// Buddy's own diaper form requires one, and a change with neither would be a no-op record).
/// Kept general (`kind`) so more one-tap log actions can be added here later.
enum QuickLogAction: String, AppEnum, CaseIterable {
    case wetDiaper, solidDiaper, wetAndSolidDiaper

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Diaper" }

    static var caseDisplayRepresentations: [QuickLogAction: DisplayRepresentation] {
        [.wetDiaper: "Wet", .solidDiaper: "Solid", .wetAndSolidDiaper: "Wet + Solid"]
    }

    /// Short label for the widget tile.
    var title: String {
        switch self {
        case .wetDiaper: return "Wet"
        case .solidDiaper: return "Solid"
        case .wetAndSolidDiaper: return "Wet + Solid"
        }
    }

    /// The record kind this action logs. Diaper change for now; kept general so more one-tap
    /// actions can be added without touching the intent.
    var kind: EntityKind { .change }

    var systemImage: String { kind.systemImage }

    /// Accent/tint for the widget tile, matching the diaper-change activity color coding.
    var tint: Color { BBColor.activity(kind) }

    /// The `wet`/`solid` pair this action sets. Always has at least one `true`, so every posted
    /// change is a real event (matching Baby Buddy's own diaper form, which requires one).
    private var flags: (wet: Bool, solid: Bool) {
        switch self {
        case .wetDiaper: return (wet: true, solid: false)
        case .solidDiaper: return (wet: false, solid: true)
        case .wetAndSolidDiaper: return (wet: true, solid: true)
        }
    }

    /// The create payload for a diaper change against `childID`, stamped to `now`. A change
    /// REQUIRES a child, so the caller must supply a valid id (the intent guards for one).
    func payload(childID: Int, now: Date) -> [String: Any] {
        [
            "child": childID,
            "time": APIDate.isoDateTime.string(from: now),
            "wet": flags.wet,
            "solid": flags.solid,
        ]
    }
}

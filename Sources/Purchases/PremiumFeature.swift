import Foundation

/// Every capability in the app that the gating system can reason about.
///
/// A feature's tier is **not** encoded here — whether a case is free or premium lives entirely in
/// ``FeatureAccess``. That keeps this enum a pure catalog: adding a new premium feature is a single
/// new `case` (it is locked for free users by default), and the display metadata below is only used
/// by the paywall.
enum PremiumFeature: String, CaseIterable, Identifiable, Sendable {
    case feeding
    case diapers
    case sleep
    case pumping
    case tummyTime
    case measurements
    case timers
    case statistics
    case widgets
    case notes
    case timelineEditing

    var id: String { rawValue }

    /// Short, user-facing name (used on the paywall).
    var title: String {
        switch self {
        case .feeding:        return "Feeding"
        case .diapers:        return "Diapers"
        case .sleep:          return "Sleep"
        case .pumping:        return "Pumping"
        case .tummyTime:      return "Tummy Time"
        case .measurements:   return "Measurements"
        case .timers:         return "Timers"
        case .statistics:     return "Statistics"
        case .widgets:        return "Home Screen Widgets"
        case .notes:          return "Notes"
        case .timelineEditing: return "Timeline Editing"
        }
    }

    /// One-line description of what the feature covers (used on the paywall).
    var summary: String {
        switch self {
        case .feeding:        return "Track bottle and nursing sessions."
        case .diapers:        return "Log diaper changes."
        case .sleep:          return "Record naps and night sleep."
        case .pumping:        return "Log pumping sessions and amounts."
        case .tummyTime:      return "Track tummy-time minutes."
        case .measurements:   return "Weight, height, and head circumference."
        case .timers:         return "Live start/stop timers for any activity."
        case .statistics:     return "Trends, insights, and breakdowns."
        case .widgets:        return "Start timers and one-tap log diapers and feeds from the Home Screen."
        case .notes:          return "Add notes and photos to your log."
        case .timelineEditing: return "Edit and delete past entries."
        }
    }

    /// SF Symbol used to illustrate the feature on the paywall.
    var systemImage: String {
        switch self {
        case .feeding:        return "cup.and.saucer.fill"
        case .diapers:        return "arrow.triangle.2.circlepath"
        case .sleep:          return "moon.zzz.fill"
        case .pumping:        return "drop.fill"
        case .tummyTime:      return "figure.child"
        case .measurements:   return "ruler.fill"
        case .timers:         return "timer"
        case .statistics:     return "chart.line.uptrend.xyaxis"
        case .widgets:        return "square.grid.2x2.fill"
        case .notes:          return "note.text"
        case .timelineEditing: return "pencil.and.list.clipboard"
        }
    }
}

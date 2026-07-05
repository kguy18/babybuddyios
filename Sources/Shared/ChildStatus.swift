import Foundation

/// At-a-glance status of one child, derived from the cached ``LocalEntity`` records — the data
/// behind the status widget. Pure (no SwiftData / SwiftUI) so it can be computed off a plain
/// array and unit-tested; the widget provider fetches from the shared store and calls
/// ``compute(from:childID:now:)``. Mirrors the Dashboard's "last event of kind" + today-count logic.
struct ChildStatus: Equatable {
    /// Whether a child is selected and present in the cache. `false` renders a "open the app" hint.
    let hasChild: Bool
    let childName: String?
    let feeding: KindStatus
    let sleep: KindStatus
    let change: KindStatus

    /// The kinds surfaced by the status widget, in display order.
    static let kinds: [EntityKind] = [.feeding, .sleep, .change]

    var all: [KindStatus] { [feeding, sleep, change] }

    /// Placeholder used when no child is selected or the store is unavailable.
    static let unavailable = ChildStatus(
        hasChild: false, childName: nil,
        feeding: .empty(.feeding), sleep: .empty(.sleep), change: .empty(.change))

    static func compute(from entities: [LocalEntity], childID: Int?, now: Date = .now) -> ChildStatus {
        guard let childID else { return .unavailable }

        let calendar = Calendar.current
        let childRecord = entities.first { $0.kind == .child && $0.serverID == childID }
        // This child's own events (the denormalized `childID` is the FK), ignoring records queued
        // for deletion — the same visibility rule the Dashboard/timeline use.
        let mine = entities.filter { $0.childID == childID && $0.syncState != .pendingDelete }

        func status(for kind: EntityKind) -> KindStatus {
            let ofKind = mine.filter { $0.kind == kind }.sorted { $0.timestamp > $1.timestamp }
            let last = ofKind.first
            let todayCount = ofKind.reduce(into: 0) { count, event in
                if calendar.isDate(event.timestamp, inSameDayAs: now) { count += 1 }
            }
            return KindStatus(kind: kind,
                              last: last?.timestamp,
                              detail: last.flatMap(EntityFormatting.subtitle),
                              todayCount: todayCount)
        }

        return ChildStatus(
            hasChild: true,
            childName: childRecord.flatMap(Self.firstName),
            feeding: status(for: .feeding),
            sleep: status(for: .sleep),
            change: status(for: .change))
    }

    /// The child's first name (falling back to last name, then "Child") — matches the Dashboard.
    private static func firstName(_ child: LocalEntity) -> String {
        let p = child.payloadObject
        let first = (p["first_name"] as? String) ?? ""
        if !first.isEmpty { return first }
        let last = (p["last_name"] as? String) ?? ""
        return last.isEmpty ? "Child" : last
    }
}

/// Per-kind slice of a child's status: when it last happened, a short detail line, and how many
/// times it happened today.
struct KindStatus: Equatable {
    let kind: EntityKind
    /// Timestamp of the most recent event of this kind, or `nil` if there are none cached.
    let last: Date?
    /// A short human detail for the most recent event (e.g. "Formula · Bottle · 20m"), or `nil`.
    let detail: String?
    let todayCount: Int

    static func empty(_ kind: EntityKind) -> KindStatus {
        KindStatus(kind: kind, last: nil, detail: nil, todayCount: 0)
    }

    /// Short caregiver-facing label for the widget ("Fed", "Slept", "Changed").
    var shortLabel: String {
        switch kind {
        case .feeding: return "Fed"
        case .sleep: return "Slept"
        case .change: return "Changed"
        default: return kind.displayName
        }
    }
}

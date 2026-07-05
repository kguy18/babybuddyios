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
    /// The child's currently-running timer, if any — drives the "timer running" header.
    let runningTimer: RunningTimer?

    /// The kinds surfaced by the status widget, in display order.
    static let kinds: [EntityKind] = [.feeding, .sleep, .change]

    var all: [KindStatus] { [feeding, sleep, change] }

    /// Placeholder used when no child is selected or the store is unavailable.
    static let unavailable = ChildStatus(
        hasChild: false, childName: nil,
        feeding: .empty(.feeding), sleep: .empty(.sleep), change: .empty(.change),
        runningTimer: nil)

    static func compute(from entities: [LocalEntity], childID: Int?, now: Date = .now) -> ChildStatus {
        guard let childID else { return .unavailable }

        let calendar = Calendar.current
        let childRecord = entities.first { $0.kind == .child && $0.serverID == childID }
        // This child's own events (the denormalized `childID` is the FK), ignoring records queued
        // for deletion — the same visibility rule the Dashboard/timeline use.
        let mine = entities.filter { $0.childID == childID && $0.syncState != .pendingDelete }

        // A running timer is a cached `.timer` record for this child (most recent wins).
        let running = mine
            .filter { $0.kind == .timer }
            .max { $0.timestamp < $1.timestamp }
            .map { timer -> RunningTimer in
                let name = (timer.payloadObject["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                return RunningTimer(name: name ?? "Timer", start: timer.timestamp)
            }

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
            change: status(for: .change),
            runningTimer: running)
    }

    /// Compact "age" of a date relative to `now` for the widget tiles ("now", "20m", "2h",
    /// "2h 15m", "1d 20h", "2d").
    static func compactAge(from date: Date, to now: Date) -> String {
        let minutes = Int(max(0, now.timeIntervalSince(date)) / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { let m = minutes % 60; return m > 0 ? "\(hours)h \(m)m" : "\(hours)h" }
        let days = hours / 24, h = hours % 24
        return h > 0 ? "\(days)d \(h)h" : "\(days)d"
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

/// A currently-running Baby Buddy timer, surfaced in the widget header.
struct RunningTimer: Equatable {
    /// The timer's name (e.g. "Sleep"); falls back to "Timer" for an unnamed timer.
    let name: String
    /// When the timer started — the widget shows live-ticking elapsed time from here.
    let start: Date
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

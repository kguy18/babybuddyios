import Foundation

/// Display time only: what a row or widget shows and how Latest sorts. Stored timestamps,
/// durations, and day totals stay start-based.
struct ActivityRecency: Equatable {
    enum Basis: Equatable {
        case event, feedEnded, woke, feedStarted, sleepStarted
        case feeding, sleeping, feedStopped, sleepStopped
    }

    let date: Date
    let basis: Basis

    static func event(kind: String, timestamp: Date, start: Date?, end: Date?, now: Date) -> Self {
        guard kind == "feeding" || kind == "sleep" else { return Self(date: timestamp, basis: .event) }
        // An absent, reversed or future end must never imply a completed session.
        if let start, let end, end >= start, end <= now {
            return Self(date: end, basis: kind == "feeding" ? .feedEnded : .woke)
        }
        return Self(date: timestamp, basis: kind == "feeding" ? .feedStarted : .sleepStarted)
    }

    static func timer(kind: String, start: Date, stoppedAt: Date?, now: Date) -> Self? {
        guard kind == "feeding" || kind == "sleep", start <= now else { return nil }
        if let stoppedAt {
            guard stoppedAt >= start, stoppedAt <= now else { return nil }
            return Self(date: stoppedAt, basis: kind == "feeding" ? .feedStopped : .sleepStopped)
        }
        return Self(date: start, basis: kind == "feeding" ? .feeding : .sleeping)
    }

    var isRunning: Bool { basis == .feeding || basis == .sleeping }

    /// The clock time, for a running timer's "since 1:10 PM". A fixed time, so it never needs a tick.
    var timeText: String { date.formatted(date: .omitted, time: .shortened) }

    var sinceText: String { String(localized: "since \(timeText)") }

    var rowLabel: String? {
        switch basis {
        case .event: return nil
        case .feedEnded: return String(localized: "Finished")
        case .woke: return String(localized: "Woke")
        case .feedStarted, .sleepStarted, .feeding, .sleeping: return String(localized: "Started")
        case .feedStopped, .sleepStopped: return String(localized: "Timer stopped")
        }
    }

    var widgetLabel: String? {
        switch basis {
        case .event: return nil
        case .feedEnded: return String(localized: "Last fed")
        case .woke: return String(localized: "Awake")
        case .feedStarted: return String(localized: "Feed started")
        case .sleepStarted: return String(localized: "Sleep started")
        case .feeding: return String(localized: "Feeding")
        case .sleeping: return String(localized: "Sleeping")
        case .feedStopped: return String(localized: "Feed stopped")
        case .sleepStopped: return String(localized: "Sleep stopped")
        }
    }

    /// The medium tile's caption. A running timer's reads into the start time below it.
    var tileLabel: String? {
        switch basis {
        case .feeding: return String(localized: "Feeding since")
        case .sleeping: return String(localized: "Sleeping since")
        default: return widgetLabel
        }
    }

    /// The whole sentence for VoiceOver, and for the inline widget while a timer runs.
    func spokenTime(now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let age = formatter.localizedString(for: date, relativeTo: now)
        switch basis {
        case .event: return age
        case .feedEnded: return String(localized: "Feeding finished \(age)")
        case .woke: return String(localized: "Woke \(age)")
        case .feedStarted: return String(localized: "Feeding started \(age)")
        case .sleepStarted: return String(localized: "Sleep started \(age)")
        case .feeding: return String(localized: "Feeding since \(timeText)")
        case .sleeping: return String(localized: "Sleeping since \(timeText)")
        case .feedStopped: return String(localized: "Feeding timer stopped \(age)")
        case .sleepStopped: return String(localized: "Sleep timer stopped \(age)")
        }
    }
}

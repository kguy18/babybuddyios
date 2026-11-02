import Foundation

/// Presentation time only. Canonical record timestamps, durations and day totals stay start-based.
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
        return Self(date: start ?? timestamp, basis: kind == "feeding" ? .feedStarted : .sleepStarted)
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

    var rowLabel: String? {
        switch basis {
        case .event: return nil
        case .feedEnded: return activityTimeText("Finished")
        case .woke: return activityTimeText("Woke")
        case .feedStarted, .sleepStarted, .feeding, .sleeping: return activityTimeText("Started")
        case .feedStopped, .sleepStopped: return activityTimeText("Timer stopped")
        }
    }

    var widgetLabel: String? {
        switch basis {
        case .event: return nil
        case .feedEnded: return activityTimeText("Feed ended")
        case .woke: return activityTimeText("Awake")
        case .feedStarted: return activityTimeText("Feed started")
        case .sleepStarted: return activityTimeText("Sleep started")
        case .feeding: return activityTimeText("Feeding")
        case .sleeping: return activityTimeText("Sleeping")
        case .feedStopped: return activityTimeText("Feed stopped")
        case .sleepStopped: return activityTimeText("Sleep stopped")
        }
    }

    func spokenTime(now: Date = .now) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        let age = formatter.localizedString(for: date, relativeTo: now)
        let key: String
        switch basis {
        case .event: return age
        case .feedEnded: key = "Feeding finished %@"
        case .woke: key = "Woke %@"
        case .feedStarted: key = "Feeding started %@"
        case .sleepStarted: key = "Sleep started %@"
        case .feeding: key = "Feeding in progress, started %@"
        case .sleeping: key = "Sleep in progress, started %@"
        case .feedStopped: key = "Feeding timer stopped %@"
        case .sleepStopped: key = "Sleep timer stopped %@"
        }
        return String(format: activityTimeText(key), locale: Locale.current, age)
    }
}

func activityTimeText(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), table: "ActivityTimes")
}

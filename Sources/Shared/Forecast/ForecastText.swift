import Foundation

func forecastText(_ key: String) -> String { String(localized: String.LocalizationValue(key), table: "Forecast") }

extension ForecastKind {
    var title: String {
        switch self {
        case .feeding: return forecastText("Next feeding")
        case .nap: return forecastText("Next nap")
        case .wake: return forecastText("Possible wake-up")
        case .change: return forecastText("Diaper logging pattern")
        }
    }
    /// The label beside the time in a Today tile's footer.
    var tileLabel: String {
        switch self {
        case .feeding, .change: return forecastText("Next")
        case .nap: return forecastText("Nap")
        case .wake: return forecastText("Wakes")
        }
    }
    /// The label before the time on the closed What's next row.
    var sectionLabel: String {
        switch self {
        case .feeding: return forecastText("Feeding")
        case .nap: return forecastText("Nap")
        case .wake: return forecastText("Wakes")
        case .change: return forecastText("Diaper")
        }
    }
    /// What VoiceOver reads for a Today tile's footer. `time` has no "~".
    func tileSpokenText(_ time: String) -> String {
        switch self {
        case .feeding, .change: return String(format: forecastText("next around %@"), time)
        case .nap: return String(format: forecastText("nap around %@"), time)
        case .wake: return String(format: forecastText("wakes around %@"), time)
        }
    }
}

extension ForecastCue.State {
    /// Why a What's next row has no window.
    var message: String {
        switch self {
        case .ready: return forecastText("Estimated window")
        case .insufficient: return forecastText("More similar entries across at least three days are needed.")
        case .irregular: return forecastText("Recent intervals vary too much for a useful estimate.")
        case .elapsed: return forecastText("The usual window has passed. There is no current estimate.")
        case .inProgress: return forecastText("An activity is in progress or waiting to be logged.")
        case .invalid: return forecastText("Check incomplete entries or sync conflicts.")
        case .stale: return forecastText("Refresh your records before using estimates.")
        }
    }
}

enum ForecastFormat {
    /// A window or time at most a day away reads as a time alone, even past midnight.
    private static func isNear(_ date: Date, _ now: Date) -> Bool { date.timeIntervalSince(now) <= 24 * 3600 }

    static func window(_ window: ForecastWindow, now: Date = .now) -> String {
        guard !isNear(window.end, now) else { return "\(time(window.start, now: now))\u{2013}\(time(window.end, now: now))" }
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: window.start, to: window.end)
    }
    static func time(_ date: Date, now: Date = .now) -> String {
        date.formatted(date: isNear(date, now) ? .omitted : .numeric, time: .shortened)
    }
    static func duration(_ seconds: Double) -> String {
        Duration.seconds(Int(seconds.rounded())).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

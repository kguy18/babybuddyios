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
}

extension ForecastCue.State {
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
    static func window(_ window: ForecastWindow) -> String {
        let formatter = DateIntervalFormatter()
        formatter.dateStyle = Calendar.current.isDate(window.start, inSameDayAs: window.end) && Calendar.current.isDateInToday(window.start)
            ? .none : .short
        formatter.timeStyle = .short
        return formatter.string(from: window.start, to: window.end)
    }
    static func duration(_ seconds: Double) -> String {
        Duration.seconds(Int(seconds.rounded())).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}

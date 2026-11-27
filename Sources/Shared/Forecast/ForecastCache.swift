import Foundation

enum ForecastCache {
    /// The records the engine can use at `now`. Rows older than its lookback, with a day to spare,
    /// are skipped on their stored `timestamp` before their payload is decoded: Home redraws this
    /// on the main thread, and decoding a whole history took long enough for the watchdog to kill
    /// the app.
    static func records(_ entities: [LocalEntity], now: Date = .now) -> [ForecastRecord] {
        let cutoff = now.addingTimeInterval(-Double(ForecastEngine.lookbackDays + 1) * 86_400)
        return entities.compactMap { entity in
            guard entity.timestamp >= cutoff, let kind = ForecastRecord.Kind(rawValue: entity.kindRaw),
                  let child = entity.childID else { return nil }
            let dates = entity.startEndDates
            let time = kind == .change ? (entity.payloadObject["time"] as? String).flatMap(APIDate.parse) : dates.start
            guard let start = time else { return nil }
            return ForecastRecord(id: entity.localID, childID: child, kind: kind, start: start,
                                  end: dates.end, nap: entity.payloadObject["nap"] as? Bool,
                                  excluded: entity.syncState == .pendingDelete, conflicted: entity.syncState == .conflicted)
        }
    }
    static func timers(_ entities: [LocalEntity]) -> [ForecastTimer] {
        entities.compactMap { entity in
            guard entity.kind == .timer, entity.syncState != .pendingDelete, let child = entity.childID else { return nil }
            let activity = TimerActivity(timer: entity)
            // Tummy time/pumping timers do not block feeding/sleep estimates.
            if activity == .tummyTime || activity == .pumping { return nil }
            let kind: ForecastRecord.Kind? = activity == .feeding ? .feeding : activity == .sleep ? .sleep : nil
            return ForecastTimer(childID: child, kind: kind, start: entity.timestamp, stopped: entity.stoppedAt != nil)
        }
    }
    static func snapshot(_ entities: [LocalEntity], childID: Int, lastSync: Date?, now: Date = .now) -> ForecastSnapshot {
        ForecastEngine().snapshot(records: records(entities, now: now), timers: timers(entities), childID: childID, lastSync: lastSync, now: now)
    }
}

enum ForecastPreferences {
    /// The master switch, off until turned on.
    static let enabledKey = "activityForecastEnabled"
    /// Where estimates show once the master switch is on. Each is on until changed.
    static let tilesKey = "activityForecastTiles"
    static let sectionKey = "activityForecastSection"
    static let widgetKey = "activityForecastWidget"
    /// Whether What's next is open. In standard defaults, so each device keeps its own; closed
    /// until opened.
    static let sectionOpenKey = "activityForecastSectionOpen"

    static var enabled: Bool {
        get { SharedDefaults.suite.bool(forKey: enabledKey) }
        set { SharedDefaults.suite.set(newValue, forKey: enabledKey) }
    }
    /// Whether estimates show in the place `key` names: the master switch, then that choice.
    static func shows(_ key: String, in defaults: UserDefaults = SharedDefaults.suite) -> Bool {
        defaults.bool(forKey: enabledKey) && defaults.object(forKey: key) as? Bool ?? true
    }
}

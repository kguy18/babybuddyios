import Foundation

enum ForecastCache {
    static func records(_ entities: [LocalEntity]) -> [ForecastRecord] {
        entities.compactMap { entity in
            guard let kind = ForecastRecord.Kind(rawValue: entity.kindRaw), let child = entity.childID else { return nil }
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
        ForecastEngine().snapshot(records: records(entities), timers: timers(entities), childID: childID, lastSync: lastSync, now: now)
    }
}

enum ForecastPreferences {
    static let enabledKey = "activityForecastEnabled"
    static var enabled: Bool {
        get { SharedDefaults.suite.bool(forKey: enabledKey) }
        set { SharedDefaults.suite.set(newValue, forKey: enabledKey) }
    }
}

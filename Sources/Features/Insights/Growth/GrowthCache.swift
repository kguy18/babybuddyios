import Foundation
import CoreFoundation

/// Read-only adapter. The API already syncs all three growth collections in full.
enum GrowthCache {
    static func samples(_ entities: [LocalEntity], calendar: Calendar = .current) -> [GrowthSample] {
        entities.compactMap { entity in
            guard let metric = GrowthMetric(rawValue: entity.kindRaw), let childID = entity.childID,
                  entity.syncState != .pendingDelete else { return nil }
            let payload = entity.payloadObject
            guard let rawDate = payload["date"] as? String,
                  let date = GrowthDate.parse(rawDate, calendar: calendar),
                  let number = payload[metric.payloadKey] as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return GrowthSample(id: entity.localID, childID: childID, metric: metric,
                                date: date, value: number.doubleValue)
        }
    }
}

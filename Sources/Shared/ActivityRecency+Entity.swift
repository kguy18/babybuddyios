import Foundation

extension LocalEntity {
    func activityRecency(now: Date = .now) -> ActivityRecency {
        let dates = startEndDates
        return ActivityRecency.event(kind: kindRaw, timestamp: timestamp,
                                     start: dates.start, end: dates.end, now: now)
    }
}

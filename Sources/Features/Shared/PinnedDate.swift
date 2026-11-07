import Foundation

/// The date a new record's fields and Home's header start from. It is today, except for DEBUG
/// launches with `BB_DEMO_DATE=yyyy-MM-dd`, where that day stands in, keeping the time of day, so
/// App Store screenshots don't carry the day they were captured. Nothing else moves: records
/// still seed relative to the real clock.
enum PinnedDate {
    static var now: Date {
        #if DEBUG
        now(pinned: ProcessInfo.processInfo.environment["BB_DEMO_DATE"], real: Date())
        #else
        Date()
        #endif
    }

    #if DEBUG
    static func now(pinned: String?, real: Date, calendar: Calendar = .current) -> Date {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = calendar.timeZone
        format.dateFormat = "yyyy-MM-dd"
        guard let pinned, let day = format.date(from: pinned) else { return real }
        return day.addingTimeInterval(real.timeIntervalSince(calendar.startOfDay(for: real)))
    }
    #endif
}

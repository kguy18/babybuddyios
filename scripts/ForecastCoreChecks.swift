import Foundation

var count = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    count += 1
    guard condition() else { fatalError(message) }
}
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let engine = ForecastEngine(calendar: calendar)
let base = ISO8601DateFormatter().date(from: "2026-06-15T00:00:00Z")!
func time(_ day: Int, _ hour: Double) -> Date { base.addingTimeInterval(Double(day) * 86400 + hour * 3600) }
func feed(_ day: Int, _ hour: Double, child: Int = 1) -> ForecastRecord {
    ForecastRecord(id: UUID(), childID: child, kind: .feeding, start: time(day, hour), end: time(day, hour + 0.25))
}
let feeds = (-7..<0).flatMap { day in [9.0, 12, 15, 18, 21].map { feed(day, $0) } } + [feed(0, 9)]
func run(_ records: [ForecastRecord], hour: Double = 10, timers: [ForecastTimer] = []) -> ForecastSnapshot {
    engine.snapshot(records: records, timers: timers, childID: 1, lastSync: time(0, hour), now: time(0, hour))
}
let feeding = run(feeds).cues.first!
check(feeding.state == .ready, "Regular feeds produce a window")
check(feeding.estimate?.window.midpoint == time(0, 12), "Feeding starts anchor the interval")
check(feeding.estimate?.observations.count == 10, "Bound sample count")
check(feeding.estimate!.distinctDays >= 3, "Evidence spans days")
check(run(feeds, hour: 15).cues.first?.state == .elapsed, "Elapsed windows do not roll forward")
check(run(feeds).expires(lastSync: time(0, 10)) == time(0, 10.25), "Widget refresh bound")
check(run(feeds).expires(lastSync: time(0, 8.01)) == time(0, 10.01), "Freshness expiry")
let nearEnd = run(feeds, hour: 12.2)
check(nearEnd.expires(lastSync: time(0, 12.2)) == nearEnd.ready.first?.window.end, "Window expiry")
check(run([feed(0, 9)]).ready.isEmpty, "Sparse records do not produce certainty")
check(run(feeds + feeds).cues.first?.estimate == feeding.estimate, "Exact duplicates do not create extra evidence")
check(run(feeds + [feed(0, 9.9, child: 2)]).cues.first?.estimate == feeding.estimate, "Child isolation")
var invalid = feed(0, 9.5)
invalid.end = nil
check(run(feeds + [invalid]).cues.first?.state == .invalid, "Missing end")
invalid.end = time(0, 13)
check(run(feeds + [invalid]).cues.first?.state == .invalid, "Future end")
invalid.end = time(0, 9.75)
invalid.conflicted = true
check(run(feeds + [invalid]).cues.first?.state == .invalid, "Conflict")
invalid.conflicted = false
invalid.excluded = true
check(run(feeds + [invalid]).cues.first?.estimate == feeding.estimate, "Pending delete")
for sync in [nil, time(-1, 10), time(1, 10)] as [Date?] {
    check(engine.snapshot(records: feeds, timers: [], childID: 1, lastSync: sync, now: time(0, 10)).ready.isEmpty, "Freshness gate")
}
for stopped in [false, true] {
    let timer = ForecastTimer(childID: 1, kind: .feeding, start: time(0, 9.5), stopped: stopped)
    check(run(feeds, timers: [timer]).cues.first?.state == .inProgress, "Running/stopped unlogged feed")
}
check(run(feeds, timers: [ForecastTimer(childID: 1, kind: nil, start: time(0, 9.5))]).ready.isEmpty, "Unknown timer")
var sleeps: [ForecastRecord] = []
for day in -7..<0 {
    sleeps.append(ForecastRecord(id: UUID(), childID: 1, kind: .sleep, start: time(day, -2), end: time(day, 7), nap: false))
    for hour in [9.0, 12, 15] {
        sleeps.append(ForecastRecord(id: UUID(), childID: 1, kind: .sleep, start: time(day, hour), end: time(day, hour + 1), nap: true))
    }
}
sleeps.append(ForecastRecord(id: UUID(), childID: 1, kind: .sleep, start: time(0, -2), end: time(0, 7), nap: false))
let nap = run(sleeps, hour: 8).cues.first { $0.kind == .nap }!
check(nap.state == .ready, "Regular nap pattern")
check(nap.estimate?.anchor == time(0, 7), "Awake interval starts at sleep END")
check(nap.estimate?.window.midpoint == time(0, 9), "Nap starts at observed wake interval")
check(nap.estimate?.usualNapSeconds != nil, "Typical nap duration")
let timer = ForecastTimer(childID: 1, kind: .sleep, start: time(0, 9))
let sleeping = run(sleeps, hour: 9.25, timers: [timer])
check(sleeping.cues.first { $0.kind == .wake }?.estimate?.window.midpoint == time(0, 10), "Wake estimate from sleep duration")
check(sleeping.cues.first { $0.kind == .nap }?.state == .inProgress, "No second nap while asleep")
check(ForecastEngine.quantile([4, 1, 3, 2], fraction: 0.5) == 2.5, "Median")
let irregular = (-7..<0).flatMap { day in [feed(day, 9), feed(day, day.isMultiple(of: 2) ? 9.1 : 14.9)] } + [feed(0, 9)]
check(run(irregular).cues.first?.state == .irregular, "Irregular patterns are suppressed")
let diapers = feeds.map { ForecastRecord(id: $0.id, childID: 1, kind: .change, start: $0.start) }
check(run(diapers).cues.first { $0.kind == .change }?.estimate?.window.midpoint == time(0, 12), "Diaper logging interval")
// Translation in time must move the prediction by the same elapsed duration.
for shift in stride(from: 60.0, through: 3600, by: 60) {
    let shifted = feeds.map { ForecastRecord(id: $0.id, childID: 1, kind: .feeding,
                                             start: $0.start.addingTimeInterval(shift), end: $0.end?.addingTimeInterval(shift)) }
    let now = time(0, 10).addingTimeInterval(shift)
    let value = engine.snapshot(records: shifted, timers: [], childID: 1, lastSync: now, now: now).ready.first!
    check(value.window.midpoint == time(0, 12).addingTimeInterval(shift), "Time-shift invariance")
}
print("Forecast core: \(count) checks passed")

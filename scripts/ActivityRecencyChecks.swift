import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    checks += 1
}
let now = Date(timeIntervalSince1970: 1_730_000_000)
for kind in ["feeding", "sleep"] {
    let started: ActivityRecency.Basis = kind == "feeding" ? .feedStarted : .sleepStarted
    let ended: ActivityRecency.Basis = kind == "feeding" ? .feedEnded : .woke
    let running: ActivityRecency.Basis = kind == "feeding" ? .feeding : .sleeping
    let stopped: ActivityRecency.Basis = kind == "feeding" ? .feedStopped : .sleepStopped
    let start = now.addingTimeInterval(-5400), end = now.addingTimeInterval(-1800)
    let result = ActivityRecency.event(kind: kind, timestamp: start, start: start, end: end, now: now)
    check(result.date == end, "A completed session must use end")
    check(now.timeIntervalSince(result.date) == 1800, "Awake/finished for 30 minutes, not 90")
    check(result.basis == ended, "The meaning must identify the end")
    check(!result.isRunning, "Completed is not running")
    for invalidEnd in [nil, start.addingTimeInterval(-1), now.addingTimeInterval(1)] as [Date?] {
        let fallback = ActivityRecency.event(kind: kind, timestamp: start, start: start, end: invalidEnd, now: now)
        check(fallback.date == start, "Invalid end falls back to start")
        check(fallback.basis == started, "Fallback must explicitly say started")
    }
    let noStart = ActivityRecency.event(kind: kind, timestamp: start, start: nil, end: end, now: now)
    check(noStart.basis == started, "Missing start cannot establish a completed interval")
    let instant = ActivityRecency.event(kind: kind, timestamp: now, start: now, end: now, now: now)
    check(instant.basis == ended, "Zero length session is valid")
    let live = ActivityRecency.timer(kind: kind, start: start, stoppedAt: nil, now: now)!
    check(live.basis == running && live.isRunning && live.date == start, "A timer counts from start")
    let frozen = ActivityRecency.timer(kind: kind, start: start, stoppedAt: end, now: now)!
    check(frozen.basis == stopped && !frozen.isRunning && frozen.date == end, "Stopped is not saved or running")
    check(ActivityRecency.timer(kind: kind, start: start, stoppedAt: now.addingTimeInterval(1), now: now) == nil,
          "Future stop ignored")
    check(ActivityRecency.timer(kind: kind, start: start, stoppedAt: start.addingTimeInterval(-1), now: now) == nil,
          "Reversed stop ignored")
    check(ActivityRecency.timer(kind: kind, start: now.addingTimeInterval(1), stoppedAt: nil, now: now) == nil,
          "Future running timer ignored")
}
for kind in ["change", "note", "weight", "height", "pumping", "tummyTime"] {
    let result = ActivityRecency.event(kind: kind, timestamp: now, start: .distantPast, end: .distantPast, now: now)
    check(result.date == now && result.basis == .event, "Unrelated events retain their time")
    check(result.rowLabel == nil && result.widgetLabel == nil, "Unrelated events retain their labels")
    check(ActivityRecency.timer(kind: kind, start: now, stoppedAt: nil, now: now) == nil, "Unrelated timer ignored")
}
// Absolute elapsed time must survive calendar boundaries and different UTC offsets.
let iso = ISO8601DateFormatter()
for (s, e, n) in [
    ("2026-10-24T23:30:00+02:00", "2026-10-25T02:30:00+01:00", "2026-10-25T03:00:00+01:00"),
    ("2026-03-29T01:30:00+01:00", "2026-03-29T03:00:00+02:00", "2026-03-29T03:30:00+02:00"),
    ("2026-11-01T23:30:00Z", "2026-11-02T00:30:00Z", "2026-11-02T01:00:00Z")
] {
    let start = iso.date(from: s)!, end = iso.date(from: e)!, current = iso.date(from: n)!
    let result = ActivityRecency.event(kind: "sleep", timestamp: start, start: start, end: end, now: current)
    check(current.timeIntervalSince(result.date) == 1800, "Timezone/DST/midnight elapsed must use actual end")
    check(result.basis == .woke, "Calendar boundary must not change meaning")
}
print("Activity recency: \(checks) checks passed")

import Foundation

enum ForecastKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case feeding, nap, wake, change
    var id: String { rawValue }
}

struct ForecastRecord: Equatable, Sendable {
    enum Kind: String, Sendable { case feeding, sleep, change }
    let id: UUID
    let childID: Int
    let kind: Kind
    let start: Date
    var end: Date?
    var nap: Bool?
    var excluded = false
    var conflicted = false
}

struct ForecastTimer: Sendable {
    let childID: Int
    /// nil means an unclassified timer; estimates are suppressed until it is classified/logged.
    let kind: ForecastRecord.Kind?
    let start: Date
    var stopped = false
}

struct ForecastWindow: Equatable, Codable, Sendable {
    let start: Date
    let end: Date
    var midpoint: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
}

struct ForecastEstimate: Equatable, Sendable {
    let kind: ForecastKind
    let window: ForecastWindow
    let anchor: Date
    /// At most ten observations in seconds, oldest first. Not a calibrated probability.
    let observations: [Double]
    let distinctDays: Int
    let medianSeconds: Double
    var usualNapSeconds: ClosedRange<Double>?
}

struct ForecastCue: Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case ready, insufficient, irregular, elapsed, inProgress, invalid, stale
    }
    let kind: ForecastKind
    let state: State
    var estimate: ForecastEstimate?
    var id: ForecastKind { kind }
}

struct ForecastSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let cues: [ForecastCue]
    var ready: [ForecastEstimate] { cues.compactMap { $0.state == .ready ? $0.estimate : nil } }
    func expires(lastSync: Date?) -> Date {
        let deadlines = [generatedAt.addingTimeInterval(15 * 60), ready.map(\.window.end).min(),
                         lastSync?.addingTimeInterval(ForecastEngine.maximumCacheAge)]
            .compactMap { $0 }.filter { $0 > generatedAt }
        return deadlines.min()!
    }
}

/// Descriptive estimates of logged routines, not age norms or a model of physiological need.
/// All dates are absolute instants; only context matching and distinct-day counts use calendar.
struct ForecastEngine {
    var calendar: Calendar = .current
    static let lookbackDays = 14
    static let maximumCacheAge: TimeInterval = 2 * 3600
    static let minimumSamples = 4
    static let minimumDays = 3
    static let maximumSamples = 10

    func snapshot(records: [ForecastRecord], timers: [ForecastTimer], childID: Int,
                  lastSync: Date?, now: Date = .now) -> ForecastSnapshot {
        guard let lastSync, now.timeIntervalSince(lastSync) >= -60,
              now.timeIntervalSince(lastSync) <= Self.maximumCacheAge else {
            return ForecastSnapshot(generatedAt: now, cues: ForecastKind.allCases.map {
                ForecastCue(kind: $0, state: .stale)
            })
        }
        let cutoff = calendar.date(byAdding: .day, value: -Self.lookbackDays, to: now)!
        let mine = records.filter { $0.childID == childID && !$0.excluded && $0.start >= cutoff && $0.start <= now }
        let active = timers.filter { $0.childID == childID }
        if active.contains(where: { $0.kind == nil }) {
            return ForecastSnapshot(generatedAt: now, cues: ForecastKind.allCases.map {
                ForecastCue(kind: $0, state: .inProgress)
            })
        }
        let feeds = unique(mine.filter { $0.kind == .feeding })
        let sleeps = unique(mine.filter { $0.kind == .sleep })
        let changes = unique(mine.filter { $0.kind == .change })
        var cues: [ForecastCue] = []
        if active.contains(where: { $0.kind == .feeding }) {
            cues.append(ForecastCue(kind: .feeding, state: .inProgress))
        } else {
            cues.append(eventCue(.feeding, records: feeds, now: now))
        }
        if let timer = active.filter({ $0.kind == .sleep }).max(by: { $0.start < $1.start }) {
            cues.append(ForecastCue(kind: .nap, state: .inProgress))
            if timer.stopped {
                cues.append(ForecastCue(kind: .wake, state: .inProgress))
            } else {
                cues.append(wakeCue(sleeps: sleeps, timer: timer, now: now))
            }
        } else {
            cues.append(napCue(sleeps: sleeps, now: now))
        }
        cues.append(eventCue(.change, records: changes, now: now))
        return ForecastSnapshot(generatedAt: now, cues: cues)
    }

    private func unique(_ records: [ForecastRecord]) -> [ForecastRecord] {
        var seen: Set<String> = []
        return records.sorted { $0.start < $1.start }.filter {
            let key = "\($0.start.timeIntervalSince1970)|\($0.end?.timeIntervalSince1970 ?? -1)|\($0.nap.map(String.init) ?? "unknown")|\($0.conflicted)"
            return seen.insert(key).inserted
        }
    }

    private func valid(_ record: ForecastRecord, now: Date) -> Bool {
        guard !record.conflicted, record.start <= now else { return false }
        if record.kind == .change { return true }
        guard let end = record.end else { return false }
        return end > record.start && end <= now && end.timeIntervalSince(record.start) <= 24 * 3600
    }

    private struct Observation {
        let seconds: Double
        let context: Date
    }

    private func eventCue(_ kind: ForecastKind, records: [ForecastRecord], now: Date) -> ForecastCue {
        guard let last = records.last else { return ForecastCue(kind: kind, state: .insufficient) }
        guard valid(last, now: now), !records.contains(where: \.conflicted) else {
            return ForecastCue(kind: kind, state: .invalid)
        }
        let intervals = zip(records, records.dropFirst()).compactMap { earlier, later -> Observation? in
            guard valid(earlier, now: now), valid(later, now: now),
                  (earlier.end ?? earlier.start) <= later.start,
                  matches(earlier.start, last.start) else { return nil }
            return Observation(seconds: later.start.timeIntervalSince(earlier.start), context: earlier.start)
        }
        return estimate(kind, observations: intervals, anchor: last.start, now: now)
    }

    private func napCue(sleeps: [ForecastRecord], now: Date) -> ForecastCue {
        guard let last = sleeps.last else { return ForecastCue(kind: .nap, state: .insufficient) }
        guard valid(last, now: now), let wake = last.end, !sleeps.contains(where: \.conflicted) else {
            return ForecastCue(kind: .nap, state: .invalid)
        }
        let gaps = zip(sleeps, sleeps.dropFirst()).compactMap { earlier, later -> Observation? in
            guard valid(earlier, now: now), valid(later, now: now), later.nap == true,
                  let end = earlier.end, later.start > end, matches(end, wake) else { return nil }
            return Observation(seconds: later.start.timeIntervalSince(end), context: end)
        }
        var cue = estimate(.nap, observations: gaps, anchor: wake, now: now)
        if var value = cue.estimate {
            let durations = sleeps.compactMap { record -> Observation? in
                guard record.nap == true, valid(record, now: now), let end = record.end,
                      matches(record.start, value.window.midpoint) else { return nil }
                return Observation(seconds: end.timeIntervalSince(record.start), context: record.start)
            }
            if let summary = summary(durations) { value.usualNapSeconds = summary.low...summary.high }
            cue.estimate = value
        }
        return cue
    }

    private func wakeCue(sleeps: [ForecastRecord], timer: ForecastTimer, now: Date) -> ForecastCue {
        guard timer.start <= now, !sleeps.contains(where: \.conflicted) else {
            return ForecastCue(kind: .wake, state: .invalid)
        }
        let durations = sleeps.compactMap { record -> Observation? in
            guard valid(record, now: now), let end = record.end, matches(record.start, timer.start) else { return nil }
            return Observation(seconds: end.timeIntervalSince(record.start), context: record.start)
        }
        return estimate(.wake, observations: durations, anchor: timer.start, now: now)
    }

    /// Match historical anchor times within three local clock hours. This is a context heuristic,
    /// not a prescribed wake window or feeding schedule.
    private func matches(_ lhs: Date, _ rhs: Date) -> Bool {
        func minute(_ date: Date) -> Int { calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date) }
        let delta = abs(minute(lhs) - minute(rhs))
        return min(delta, 1440 - delta) <= 180
    }

    private struct Summary {
        let values: [Double]
        let days: Int
        let median: Double
        let low: Double
        let high: Double
        let irregular: Bool
    }

    private func summary(_ observations: [Observation]) -> Summary? {
        let recent = Array(observations.filter { $0.seconds.isFinite && $0.seconds > 0 && $0.seconds <= 24 * 3600 }
            .suffix(Self.maximumSamples))
        let days = Set(recent.map { calendar.startOfDay(for: $0.context) }).count
        guard recent.count >= Self.minimumSamples, days >= Self.minimumDays else { return nil }
        let values = recent.map(\.seconds)
        let middle = Self.quantile(values, fraction: 0.5)
        let mad = Self.quantile(values.map { abs($0 - middle) }, fraction: 0.5)
        let iqr = Self.quantile(values, fraction: 0.75) - Self.quantile(values, fraction: 0.25)
        let padding = max(5 * 60, middle * 0.1)
        return Summary(values: values, days: days, median: middle,
                       low: max(0, Self.quantile(values, fraction: 0.2) - padding),
                       high: Self.quantile(values, fraction: 0.8) + padding,
                       irregular: mad / middle > 0.35 || iqr / middle > 0.65)
    }

    private func estimate(_ kind: ForecastKind, observations: [Observation], anchor: Date, now: Date) -> ForecastCue {
        guard let summary = summary(observations) else { return ForecastCue(kind: kind, state: .insufficient) }
        guard !summary.irregular else { return ForecastCue(kind: kind, state: .irregular) }
        let window = ForecastWindow(start: anchor.addingTimeInterval(summary.low), end: anchor.addingTimeInterval(summary.high))
        let value = ForecastEstimate(kind: kind, window: window, anchor: anchor,
                                     observations: summary.values, distinctDays: summary.days,
                                     medianSeconds: summary.median)
        return ForecastCue(kind: kind, state: window.end <= now ? .elapsed : .ready, estimate: value)
    }

    static func quantile(_ values: [Double], fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let position = Double(sorted.count - 1) * min(1, max(0, fraction))
        let low = Int(position), high = min(low + 1, sorted.count - 1)
        return sorted[low] + (sorted[high] - sorted[low]) * (position - Double(low))
    }
}

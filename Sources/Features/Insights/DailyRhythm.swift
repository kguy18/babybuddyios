import Foundation

enum DailyRhythmPreferences {
    static let visibleKey = "showDailyRhythm"
    static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "DailyRhythm")
    }
}

struct RhythmSleep: Identifiable {
    let entityID: UUID
    let start: Date
    let end: Date
    let startHour: Double
    let endHour: Double
    var id: String { "\(entityID)-\(start.timeIntervalSince1970)" }
}

struct RhythmFeeding: Identifiable {
    let id: UUID
    let time: Date
    let hour: Double
    let method: FeedingMethod?
}

struct RhythmDay: Identifiable {
    let day: Date
    var sleeps: [RhythmSleep] = []
    var feedings: [RhythmFeeding] = []
    var id: Date { day }
    var axisID: String { String(day.timeIntervalSince1970) }
}

/// Local clock time on the horizontal axis, calendar days on the vertical one. Split at
/// midnight and offset transitions, so a repeated hour is not drawn as a negative interval.
struct DailyRhythmAggregator {
    var calendar: Calendar = .current

    func days(_ entities: [LocalEntity], childID: Int, period: ChartPeriod,
              now: Date = .now) -> [RhythmDay] {
        var rows = ChartAggregator(calendar: calendar).days(for: period, now: now).map { RhythmDay(day: $0) }
        guard let windowStart = rows.first?.day else { return rows }
        for entity in entities where entity.childID == childID && entity.syncState != .pendingDelete {
            switch entity.kind {
            case .feeding:
                guard let start = entity.startEndDates.start, start >= windowStart, start <= now,
                      let index = rows.firstIndex(where: { calendar.isDate($0.day, inSameDayAs: start) }) else { continue }
                rows[index].feedings.append(RhythmFeeding(
                    id: entity.localID, time: start, hour: hour(start),
                    method: (entity.payloadObject["method"] as? String).flatMap(FeedingMethod.init(rawValue:))))
            case .sleep:
                guard let start = entity.startEndDates.start, let end = entity.startEndDates.end,
                      end > start, end > windowStart, start < now else { continue }
                var cursor = max(start, windowStart)
                let limit = min(end, now)
                while cursor < limit {
                    guard let dayInterval = calendar.dateInterval(of: .day, for: cursor),
                          let index = rows.firstIndex(where: { $0.day == dayInterval.start }) else { break }
                    var next = min(dayInterval.end, limit)
                    if let transition = calendar.timeZone.nextDaylightSavingTimeTransition(after: cursor),
                       transition > cursor, transition < next { next = transition }
                    // The instant just before the endpoint belongs to this segment's offset.
                    let endHour = next == dayInterval.end ? 24 : hour(next.addingTimeInterval(-0.001)) + 0.001 / 3600
                    rows[index].sleeps.append(RhythmSleep(entityID: entity.localID, start: cursor, end: next,
                                                        startHour: hour(cursor), endHour: min(24, endHour)))
                    cursor = next
                }
            default: break
            }
        }
        for index in rows.indices {
            rows[index].sleeps.sort { $0.start < $1.start }
            rows[index].feedings.sort { $0.time < $1.time }
        }
        return rows
    }

    private func hour(_ date: Date) -> Double {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        return Double(parts.hour ?? 0) + Double(parts.minute ?? 0) / 60
            + Double(parts.second ?? 0) / 3600 + Double(parts.nanosecond ?? 0) / 3_600_000_000_000
    }
}

import Foundation

/// The rolling window a Trends chart covers.
enum ChartPeriod: Int, CaseIterable, Identifiable {
    case week = 7
    case twoWeeks = 14
    case month = 30

    var id: Int { rawValue }
    var days: Int { rawValue }

    /// Compact segmented-control label.
    var label: String { String(localized: "\(rawValue)d") }
    /// Spoken label for accessibility.
    var accessibilityLabel: String { String(localized: "\(rawValue) days") }
}

/// One day's total sleep, in hours.
struct DailySleep: Identifiable, Equatable {
    let day: Date
    let hours: Double
    var id: Date { day }
}

/// One day's total tummy time, in minutes.
struct DailyTummyTime: Identifiable, Equatable {
    let day: Date
    let minutes: Double
    var id: Date { day }
}

/// One day's feeding or pumping tally: how many sessions and the total recorded amount (ml).
struct DailyTally: Identifiable, Equatable {
    let day: Date
    let count: Int
    /// Sum of the `amount` field across the day's records; 0 when none carried an amount.
    let totalAmount: Double
    var id: Date { day }
}

/// One day's diaper-change tally, split by attribute. A single change can be both wet and
/// solid, so it is counted in both totals (matching the Baby Buddy web charts).
struct DailyDiaper: Identifiable, Equatable {
    let day: Date
    let wet: Int
    let solid: Int
    var id: Date { day }

    var total: Int { wet + solid }
}

/// One medicine on the temperature chart's legend.
struct DoseTally: Identifiable, Equatable {
    /// The normalized name, which is also the key its color is kept under.
    let id: String
    let name: String
    let count: Int
}

/// Pure, read-only aggregation of cached ``LocalEntity`` records into per-day chart series for
/// the Trends screen. Bucketing uses the denormalized `timestamp` (each kind's primary time
/// field), so an event lands on the calendar day it started/occurred. `calendar` is injectable
/// so tests can pin a fixed time zone.
struct ChartAggregator {
    var calendar: Calendar = .current

    /// Inclusive list of day-start dates covering the trailing `period`, oldest → newest and
    /// always ending on today. Always exactly `period.days` entries so the charts render empty
    /// days rather than collapsing gaps.
    func days(for period: ChartPeriod, now: Date = .now) -> [Date] {
        let today = calendar.startOfDay(for: now)
        return (0..<period.days).reversed().compactMap {
            calendar.date(byAdding: .day, value: -$0, to: today)
        }
    }

    /// Total logged sleep per day, in hours, from start/end intervals.
    func sleepHoursByDay(_ entities: [LocalEntity], childID: Int,
                         period: ChartPeriod, now: Date = .now) -> [DailySleep] {
        let seconds = durationSecondsByDay(entities, kind: .sleep, childID: childID)
        return days(for: period, now: now).map {
            DailySleep(day: $0, hours: (seconds[$0] ?? 0) / 3600)
        }
    }

    /// Total logged tummy time per day, in minutes, from start/end intervals.
    func tummyTimeMinutesByDay(_ entities: [LocalEntity], childID: Int,
                               period: ChartPeriod, now: Date = .now) -> [DailyTummyTime] {
        let seconds = durationSecondsByDay(entities, kind: .tummyTime, childID: childID)
        return days(for: period, now: now).map {
            DailyTummyTime(day: $0, minutes: (seconds[$0] ?? 0) / 60)
        }
    }

    /// Feeding count and total amount (ml) per day.
    func feedingsByDay(_ entities: [LocalEntity], childID: Int,
                       period: ChartPeriod, now: Date = .now) -> [DailyTally] {
        tally(entities, kind: .feeding, childID: childID, period: period, now: now)
    }

    /// Pumping session count and total amount (ml) per day.
    func pumpingByDay(_ entities: [LocalEntity], childID: Int,
                      period: ChartPeriod, now: Date = .now) -> [DailyTally] {
        tally(entities, kind: .pumping, childID: childID, period: period, now: now)
    }

    private func tally(_ entities: [LocalEntity], kind: EntityKind, childID: Int,
                       period: ChartPeriod, now: Date) -> [DailyTally] {
        var counts = [Date: Int]()
        var amounts = [Date: Double]()
        for entity in matching(entities, kind: kind, childID: childID) {
            let day = calendar.startOfDay(for: entity.timestamp)
            counts[day, default: 0] += 1
            // JSON numbers decode as NSNumber, so a stored int or double both bridge to Double;
            // a null/absent amount does not, and is simply left out of the sum.
            if let amount = entity.payloadObject["amount"] as? Double {
                amounts[day, default: 0] += amount
            }
        }
        return days(for: period, now: now).map {
            DailyTally(day: $0, count: counts[$0] ?? 0, totalAmount: amounts[$0] ?? 0)
        }
    }

    /// Diaper changes per day, split into wet vs solid tallies.
    func diaperChangesByDay(_ entities: [LocalEntity], childID: Int,
                            period: ChartPeriod, now: Date = .now) -> [DailyDiaper] {
        var wet = [Date: Int]()
        var solid = [Date: Int]()
        for entity in matching(entities, kind: .change, childID: childID) {
            let day = calendar.startOfDay(for: entity.timestamp)
            let payload = entity.payloadObject
            if payload["wet"] as? Bool == true { wet[day, default: 0] += 1 }
            if payload["solid"] as? Bool == true { solid[day, default: 0] += 1 }
        }
        return days(for: period, now: now).map {
            DailyDiaper(day: $0, wet: wet[$0] ?? 0, solid: solid[$0] ?? 0)
        }
    }

    // MARK: Temperature

    /// The child's temperature readings in the window, oldest first, read in `unit`.
    func temperatures(_ entities: [LocalEntity], childID: Int, period: ChartPeriod,
                      unit: TemperatureUnit, now: Date = .now) -> [SickMode.Reading] {
        SickMode.readings(inWindow(entities, kind: .temperature, childID: childID, period: period, now: now),
                          unit: unit)
    }

    /// The child's medication doses in the window, oldest first.
    func doses(_ entities: [LocalEntity], childID: Int, period: ChartPeriod,
               now: Date = .now) -> [LocalEntity] {
        inWindow(entities, kind: .medication, childID: childID, period: period, now: now)
    }

    /// The medicines among `doses`, in the order their first dose appears, with how many doses each
    /// one has. Names are matched the way ``MedicationReminderPolicy`` matches them, so "Tylenol "
    /// and "tylenol" are one medicine, spelled the way its first dose spells it.
    func doseTallies(_ doses: [LocalEntity]) -> [DoseTally] {
        var order: [String] = []
        var names = [String: String]()
        var counts = [String: Int]()
        for dose in doses {
            let spelled = (dose.payloadObject["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
            let key = MedicationReminderPolicy.normalizedName(spelled)
            if counts[key] == nil {
                order.append(key)
                names[key] = spelled.isEmpty ? String(localized: "Medication") : spelled
            }
            counts[key, default: 0] += 1
        }
        return order.map { DoseTally(id: $0, name: names[$0]!, count: counts[$0]!) }
    }

    /// One kind's records for one child from the window's first day up to `now`, oldest first.
    /// These carry their own time onto the chart rather than being bucketed into a day.
    private func inWindow(_ entities: [LocalEntity], kind: EntityKind, childID: Int,
                          period: ChartPeriod, now: Date) -> [LocalEntity] {
        let start = days(for: period, now: now)[0]
        return matching(entities, kind: kind, childID: childID)
            .filter { $0.timestamp >= start && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: Helpers

    /// Records of one kind for one child that still count toward totals (locally-deleted
    /// records are excluded, matching what the rest of the UI shows).
    private func matching(_ entities: [LocalEntity], kind: EntityKind, childID: Int) -> [LocalEntity] {
        entities.filter {
            $0.kind == kind && $0.childID == childID && $0.syncState != .pendingDelete
        }
    }

    /// Summed start→end seconds per calendar day for one kind.
    private func durationSecondsByDay(_ entities: [LocalEntity], kind: EntityKind,
                                      childID: Int) -> [Date: Double] {
        var seconds = [Date: Double]()
        for entity in matching(entities, kind: kind, childID: childID) {
            guard let interval = durationSeconds(entity) else { continue }
            seconds[calendar.startOfDay(for: entity.timestamp), default: 0] += interval
        }
        return seconds
    }

    /// Seconds between a payload's `start` and `end`, or nil if they don't form a positive
    /// interval. Mirrors ``EntityFormatting``'s start/end duration derivation, and reads the
    /// entity's parsed-date cache so re-aggregation doesn't re-parse ISO strings.
    private func durationSeconds(_ entity: LocalEntity) -> Double? {
        let dates = entity.startEndDates
        guard let start = dates.start, let end = dates.end, end > start else { return nil }
        return end.timeIntervalSince(start)
    }
}

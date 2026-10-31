import Foundation

enum GrowthMetric: String, Codable, CaseIterable, Identifiable {
    case weight, height, headCircumference
    var id: String { rawValue }
    var payloadKey: String { self == .headCircumference ? "head_circumference" : rawValue }
}

enum GrowthPeriod: Int, CaseIterable, Identifiable {
    case month = 30, threeMonths = 90, year = 365, all = 0
    var id: Int { rawValue }
}

enum GrowthWeightUnit: String, Codable, CaseIterable {
    case kilograms, grams, pounds
    var symbol: String {
        switch self {
        case .kilograms: return "kg"
        case .grams: return "g"
        case .pounds: return "lb"
        }
    }
    func kilograms(_ value: Double) -> Double {
        switch self {
        case .kilograms: return value
        case .grams: return value / 1000
        case .pounds: return value * 0.45359237
        }
    }
    func display(_ kilograms: Double) -> Double {
        switch self {
        case .kilograms: return kilograms
        case .grams: return kilograms * 1000
        case .pounds: return kilograms / 0.45359237
        }
    }
}

enum GrowthLengthUnit: String, Codable, CaseIterable {
    case centimeters, inches
    var symbol: String { self == .centimeters ? "cm" : "in" }
    func centimeters(_ value: Double) -> Double { self == .centimeters ? value : value * 2.54 }
}

struct GrowthSample: Identifiable, Equatable {
    let id: UUID
    let childID: Int
    let metric: GrowthMetric
    let date: Date
    /// The unmodified server value, not presumed to be metric until units are confirmed.
    let value: Double
    var excluded = false
}

/// Date-only API fields are calendar dates, never UTC instants shifted into yesterday.
enum GrowthDate {
    static func parse(_ raw: String, calendar: Calendar = .current) -> Date? {
        let parts = raw.split(separator: "-", omittingEmptySubsequences: false)
        guard raw.count == 10, parts.count == 3, parts[0].count == 4,
              parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), year > 0 else { return nil }
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = gregorian.date(from: components),
              gregorian.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return date
    }

    static func string(_ date: Date, calendar: Calendar = .current) -> String {
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = calendar.timeZone
        let c = gregorian.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func ageDays(birth: Date, date: Date, calendar: Calendar = .current) -> Int? {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: birth),
                                to: calendar.startOfDay(for: date)).day
    }
}

struct GrowthSeries {
    var calendar: Calendar = .current

    func samples(_ samples: [GrowthSample], childID: Int, metric: GrowthMetric,
                 period: GrowthPeriod, now: Date = .now) -> [GrowthSample] {
        let today = calendar.startOfDay(for: now)
        let start = period == .all ? Date.distantPast
            : calendar.date(byAdding: .day, value: 1 - period.rawValue, to: today)!
        return samples.filter {
            $0.childID == childID && $0.metric == metric && !$0.excluded
                && $0.value.isFinite && $0.value > 0 && $0.date >= start && $0.date <= today
        }.sorted {
            $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
        }
    }

    /// One visible point per actual record. Missing days are never zero-filled or averaged.
    func xDomain(_ samples: [GrowthSample], period: GrowthPeriod, now: Date = .now) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        let first = period == .all ? samples.first?.date ?? today
            : calendar.date(byAdding: .day, value: 1 - period.rawValue, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!
        return first...end
    }

    /// A nonzero, padded span even for one point or a constant series. No forced zero baseline.
    static func yDomain(_ values: [Double]) -> ClosedRange<Double> {
        let values = values.filter { $0.isFinite && $0 > 0 }
        guard let low = values.min(), let high = values.max() else { return 0...1 }
        let padding = max((high - low) * 0.15, high * 0.03, 0.001)
        return max(0, low - padding)...(high + padding)
    }
}

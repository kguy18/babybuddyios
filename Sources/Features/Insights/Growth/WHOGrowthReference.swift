import Foundation

/// WHO Child Growth Standards, expanded daily tables, ages 0...1856 days.
/// Rows: day, L, M, S, P3, P15, P50, P85, P97. Curves use the published centiles directly.
struct WHOGrowthReference: Decodable {
    struct Table: Decodable {
        let metric: GrowthMetric
        let sex: GrowthReferenceSex
        let source: String
        let sha256: String
        let rows: [[Double]]
    }
    struct Point: Identifiable {
        let date: Date
        let value: Double
        let percentile: Int
        let day: Int
        let segment: String
        var id: String { "\(percentile)-\(day)" }
    }
    let tables: [Table]
    static let percentiles = [3, 15, 50, 85, 97]
    static let maximumDay = 1856

    static func load(bundle: Bundle = .main) -> WHOGrowthReference? {
        guard let url = bundle.url(forResource: "who-growth-reference", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let reference = try? JSONDecoder().decode(Self.self, from: data), reference.isValid else { return nil }
        return reference
    }

    var isValid: Bool {
        guard tables.count == 6 else { return false }
        for metric in GrowthMetric.allCases {
            for sex in [GrowthReferenceSex.girls, .boys] {
                guard let table = tables.first(where: { $0.metric == metric && $0.sex == sex }),
                      table.rows.count == Self.maximumDay + 1 else { return false }
                for (day, row) in table.rows.enumerated() {
                    guard row.count == 9, row[0] == Double(day), row.allSatisfy(\.isFinite),
                          row[2] > 0, row[3] > 0,
                          row[4...8].allSatisfy({ $0 > 0 }),
                          Array(row[4...8]) == row[4...8].sorted() else { return false }
                }
            }
        }
        return true
    }

    func row(metric: GrowthMetric, sex: GrowthReferenceSex, day: Int) -> [Double]? {
        guard (0...Self.maximumDay).contains(day) else { return nil }
        return tables.first { $0.metric == metric && $0.sex == sex }?.rows[day]
    }

    func points(metric: GrowthMetric, sex: GrowthReferenceSex, birth: Date,
                domain: ClosedRange<Date>, calendar: Calendar = .current,
                maximumPointsPerCurve: Int? = nil) -> [Point] {
        guard let first = GrowthDate.ageDays(birth: birth, date: domain.lowerBound, calendar: calendar),
              let last = GrowthDate.ageDays(birth: birth, date: domain.upperBound, calendar: calendar),
              last >= 0, first <= Self.maximumDay else { return [] }
        var points: [Point] = []
        let lower = max(0, first), upper = min(Self.maximumDay, last)
        let step = maximumPointsPerCurve.map { max(1, (upper - lower) / max(1, $0)) } ?? 1
        for day in lower...upper {
            // Long histories need fewer marks at phone resolution. Keep the rapid early changes
            // daily, both endpoints and both sides of the length/height transition exactly.
            if day > 90 && day != lower && day != upper && day != 730 && day != 731 && day % step != 0 { continue }
            guard let row = row(metric: metric, sex: sex, day: day),
                  let date = calendar.date(byAdding: .day, value: day, to: birth) else { continue }
            for (index, percentile) in Self.percentiles.enumerated() {
                // WHO's length-to-standing-height discontinuity must not be joined by a line.
                let phase = metric == .height && day > 730 ? "height" : "length"
                points.append(Point(date: date, value: row[4 + index], percentile: percentile,
                                    day: day, segment: "P\(percentile)-\(phase)"))
            }
        }
        return points
    }

    /// Used to independently verify the published centiles against their LMS coefficients.
    /// Only central centiles are needed; no tail extrapolation or individual classification.
    static func value(l: Double, m: Double, s: Double, z: Double) -> Double? {
        guard [l, m, s, z].allSatisfy(\.isFinite), m > 0, s > 0, abs(z) <= 3 else { return nil }
        if abs(l) < 1e-10 { return m * exp(s * z) }
        let base = 1 + l * s * z
        guard base > 0 else { return nil }
        let result = m * pow(base, 1 / l)
        return result.isFinite ? result : nil
    }
}

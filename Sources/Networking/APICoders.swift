import Foundation

/// JSON encoder/decoder configured for Baby Buddy's Django REST Framework output.
///
/// DRF renders datetimes as ISO-8601 with a timezone offset and *optional* fractional
/// seconds (e.g. `2024-01-15T10:30:00.123456-05:00` or `2024-01-15T10:30:00-05:00`),
/// and plain dates as `YYYY-MM-DD`. We register tolerant strategies that round-trip both.
///
/// Note: Baby Buddy's `tags` field is a plain `[String]` on both read and write
/// (DRF `TagListSerializerField`), and `child` foreign keys are integer PKs — so no
/// custom container types are needed beyond date handling.
enum APICoders {
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = APIDate.parse(raw) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognized date format: \(raw)")
        }
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(APIDate.isoDateTime.string(from: date))
        }
        return e
    }()
}

/// Date parsing/formatting helpers shared across DTOs.
enum APIDate {
    /// Full datetime with timezone, no fractional seconds (used for encoding writes).
    static let isoDateTime: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// `YYYY-MM-DD` (birth_date and measurement dates can be date-only).
    static let dateOnly: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(secondsFromGMT: 0)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ raw: String) -> Date? {
        if let d = isoFractional.date(from: raw) { return d }
        if let d = isoDateTime.date(from: raw) { return d }
        if let d = dateOnly.date(from: raw) { return d }
        return nil
    }
}

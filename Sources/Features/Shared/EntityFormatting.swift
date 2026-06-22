import Foundation

/// Renders a cached ``LocalEntity`` payload into human-readable text for lists and cards.
enum EntityFormatting {
    static func title(_ entity: LocalEntity) -> String {
        entity.kind.displayName
    }

    static func subtitle(_ entity: LocalEntity) -> String? {
        let p = entity.payloadObject
        let base = baseSubtitle(entity, p)
        guard let tagSuffix = tagsLine(p) else { return base }
        guard let base, !base.isEmpty else { return tagSuffix }
        return base + " · " + tagSuffix
    }

    /// Tag names rendered for list subtitles, e.g. `#hungry #night`. Nil when there are none.
    private static func tagsLine(_ p: [String: Any]) -> String? {
        guard let tags = p["tags"] as? [String], !tags.isEmpty else { return nil }
        return tags.map { "#\($0)" }.joined(separator: " ")
    }

    private static func baseSubtitle(_ entity: LocalEntity, _ p: [String: Any]) -> String? {
        switch entity.kind {
        case .feeding:
            var parts: [String] = []
            if let t = p["type"] as? String { parts.append(t.capitalized) }
            if let m = p["method"] as? String { parts.append(m.capitalized) }
            if let d = duration(p) { parts.append(d) }
            if let a = p["amount"] as? Double { parts.append(formatAmount(a)) }
            return parts.joined(separator: " · ")
        case .change:
            var flags: [String] = []
            if p["wet"] as? Bool == true { flags.append("Wet") }
            if p["solid"] as? Bool == true { flags.append("Solid") }
            if let color = p["color"] as? String, !color.isEmpty { flags.append(color.capitalized) }
            return flags.isEmpty ? "Dry" : flags.joined(separator: ", ")
        case .sleep:
            var parts: [String] = []
            if let d = duration(p) { parts.append(d) }
            if p["nap"] as? Bool == true { parts.append("Nap") }
            return parts.joined(separator: " · ")
        case .tummyTime:
            var parts: [String] = []
            if let d = duration(p) { parts.append(d) }
            if let m = p["milestone"] as? String, !m.isEmpty { parts.append(m) }
            return parts.joined(separator: " · ")
        case .pumping:
            var parts: [String] = []
            if let d = duration(p) { parts.append(d) }
            if let a = p["amount"] as? Double { parts.append(formatAmount(a)) }
            return parts.joined(separator: " · ")
        case .note:
            return p["note"] as? String
        case .timer:
            return p["name"] as? String
        case .weight:
            return (p["weight"] as? Double).map { "\(trim($0))" }
        case .height:
            return (p["height"] as? Double).map { "\(trim($0))" }
        case .headCircumference:
            return (p["head_circumference"] as? Double).map { "\(trim($0))" }
        case .temperature:
            return (p["temperature"] as? Double).map { "\(trim($0))°" }
        case .bmi:
            return (p["bmi"] as? Double).map { "\(trim($0))" }
        case .medication:
            var parts: [String] = []
            if let n = p["name"] as? String { parts.append(n) }
            if let dose = p["dosage"] as? Double {
                let unit = p["dosage_unit"] as? String ?? ""
                parts.append("\(trim(dose)) \(unit)".trimmingCharacters(in: .whitespaces))
            }
            return parts.joined(separator: " · ")
        case .child:
            return nil
        }
    }

    // MARK: Helpers

    static func formatAmount(_ value: Double) -> String { "\(trim(value)) ml" }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Prefer a start/end derived duration; fall back to the server's `duration` string.
    private static func duration(_ p: [String: Any]) -> String? {
        if let s = p["start"] as? String, let e = p["end"] as? String,
           let start = APIDate.parse(s), let end = APIDate.parse(e), end > start {
            return formatInterval(end.timeIntervalSince(start))
        }
        if let raw = p["duration"] as? String { return raw }
        return nil
    }

    static func formatInterval(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }
}

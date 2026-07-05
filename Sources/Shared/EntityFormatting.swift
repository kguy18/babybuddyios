import Foundation

/// Renders a cached ``LocalEntity`` payload into human-readable text for lists and cards.
enum EntityFormatting {
    static func title(_ entity: LocalEntity) -> String {
        entity.kind.displayName
    }

    static func subtitle(_ entity: LocalEntity) -> String? {
        let p = entity.payloadObject
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

    /// The record's tag names, in payload order. Empty when there are none.
    static func tags(_ entity: LocalEntity) -> [String] {
        (entity.payloadObject["tags"] as? [String]) ?? []
    }

    /// A single spoken VoiceOver phrase for a timeline/latest row: kind, its detail, the time,
    /// then sync state and tags — so the row reads as one coherent element instead of fragments.
    static func accessibilityLabel(_ entity: LocalEntity) -> String {
        var parts: [String] = [title(entity)]
        if let subtitle = subtitle(entity), !subtitle.isEmpty { parts.append(subtitle) }
        parts.append(entity.timestamp.formatted(date: .omitted, time: .shortened))
        switch entity.syncState {
        case .pendingCreate, .pendingUpdate, .pendingDelete: parts.append("waiting to sync")
        case .conflicted: parts.append("sync conflict")
        case .synced: break
        }
        let names = tags(entity)
        if !names.isEmpty { parts.append("tags: \(names.joined(separator: ", "))") }
        return parts.joined(separator: ", ")
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

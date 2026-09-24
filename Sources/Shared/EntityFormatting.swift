import Foundation

/// Renders a cached ``LocalEntity`` payload into human-readable text for lists and cards.
enum EntityFormatting {
    static func title(_ entity: LocalEntity) -> String {
        entity.kind.displayName
    }

    static func subtitle(_ entity: LocalEntity) -> String? { subtitle(entity, unit: .current) }

    /// `unit` is the phone's temperature unit; a row that watches the setting passes it, so it
    /// redraws when the setting changes.
    static func subtitle(_ entity: LocalEntity, unit: TemperatureUnit) -> String? {
        let p = entity.payloadObject
        switch entity.kind {
        case .feeding:
            var parts: [String] = []
            if let t = p["type"] as? String { parts.append(t.capitalized) }
            if let m = p["method"] as? String { parts.append(m.capitalized) }
            if let d = duration(entity) { parts.append(d) }
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
            if let d = duration(entity) { parts.append(d) }
            if p["nap"] as? Bool == true { parts.append("Nap") }
            return parts.joined(separator: " · ")
        case .tummyTime:
            var parts: [String] = []
            if let d = duration(entity) { parts.append(d) }
            if let m = p["milestone"] as? String, !m.isEmpty { parts.append(m) }
            return parts.joined(separator: " · ")
        case .pumping:
            var parts: [String] = []
            if let d = duration(entity) { parts.append(d) }
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
            return (p["temperature"] as? Double).map { unit.format(unit.reading($0)) }
        case .bmi:
            return (p["bmi"] as? Double).map { "\(trim($0))" }
        case .medication:
            return [p["name"] as? String, dosage(entity)].compactMap { $0 }.joined(separator: " · ")
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
    /// `blocked`: the server refused the queued write — what the row's red triangle shows, and not
    /// something that will sync by waiting.
    static func accessibilityLabel(_ entity: LocalEntity, blocked: Bool = false) -> String {
        var parts: [String] = [title(entity)]
        if let subtitle = subtitle(entity), !subtitle.isEmpty { parts.append(subtitle) }
        parts.append(entity.timestamp.formatted(date: .omitted, time: .shortened))
        switch entity.syncState {
        case .pendingCreate, .pendingUpdate, .pendingDelete:
            parts.append(blocked ? "sync needs attention" : "waiting to sync")
        case .conflicted: parts.append("sync conflict")
        case .synced: break
        }
        let names = tags(entity)
        if !names.isEmpty { parts.append("tags: \(names.joined(separator: ", "))") }
        return parts.joined(separator: ", ")
    }

    // MARK: Helpers

    static func formatAmount(_ value: Double) -> String { "\(trim(value)) ml" }

    /// A dose's amount and unit, "5 mL", or `nil` when it has no dosage.
    static func dosage(_ entity: LocalEntity) -> String? {
        let p = entity.payloadObject
        guard let dose = p["dosage"] as? Double else { return nil }
        return "\(trim(dose)) \(p["dosage_unit"] as? String ?? "")".trimmingCharacters(in: .whitespaces)
    }

    private static func trim(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Prefer a start/end derived duration (via the entity's parsed-date cache); fall back to
    /// the server's `duration` string.
    private static func duration(_ entity: LocalEntity) -> String? {
        let dates = entity.startEndDates
        if let start = dates.start, let end = dates.end, end > start {
            return formatInterval(end.timeIntervalSince(start))
        }
        if let raw = entity.payloadObject["duration"] as? String { return raw }
        return nil
    }

    /// A stopped timer's elapsed time, laid out like a running one's `Text(_:style: .timer)`.
    static func clock(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(max(seconds, 0)))
            .formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
    }

    /// The same elapsed time as VoiceOver should read it: "25 minutes, 13 seconds".
    static func spokenDuration(_ seconds: TimeInterval) -> String {
        Duration.seconds(Int(max(seconds, 0)))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    static func formatInterval(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }
}

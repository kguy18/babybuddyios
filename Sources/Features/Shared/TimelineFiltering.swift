import Foundation

/// Pure, offline matching for the timeline's text search and date-range filters. Factored out
/// of the view so it's unit-testable and runs entirely over the local cache (no network) —
/// search only ever sees what's been pulled (pair with "Load older" to reach deeper history).
enum TimelineFiltering {
    /// Lowercased searchable text for an entity: its rendered title/subtitle (which already
    /// encode type/method/diaper flags/measurement values), its tags, any free-text note(s),
    /// and the owning child's name. Joined for case-insensitive substring search.
    static func haystack(for entity: LocalEntity, childName: String?) -> String {
        var parts = [EntityFormatting.title(entity)]
        if let subtitle = EntityFormatting.subtitle(entity), !subtitle.isEmpty { parts.append(subtitle) }
        parts.append(contentsOf: EntityFormatting.tags(entity))
        let payload = entity.payloadObject
        for key in ["note", "notes"] {
            if let text = payload[key] as? String, !text.isEmpty { parts.append(text) }
        }
        if let childName, !childName.isEmpty { parts.append(childName) }
        return parts.joined(separator: " ").lowercased()
    }

    /// Whether the entity matches a free-text query. The query is split into whitespace tokens
    /// and every token must appear (AND), so "formula bottle" matches a feeding even though the
    /// words aren't adjacent in the rendered text. A blank query matches everything.
    static func matchesSearch(_ entity: LocalEntity, query: String, childName: String?) -> Bool {
        let tokens = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return true }
        let hay = haystack(for: entity, childName: childName)
        return tokens.allSatisfy { hay.contains($0) }
    }

    /// Whether `timestamp` falls within an inclusive `[from, to]` day range. Each bound is a
    /// whole day: `from` includes everything from its start-of-day; `to` includes everything up
    /// to (but not including) the start of the following day. Either bound may be nil
    /// (open-ended). `calendar` is injectable for deterministic tests.
    static func inDateRange(_ timestamp: Date, from: Date?, to: Date?,
                            calendar: Calendar = .current) -> Bool {
        if let from, timestamp < calendar.startOfDay(for: from) { return false }
        if let to {
            let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: to))
            if let endExclusive, timestamp >= endExclusive { return false }
        }
        return true
    }
}

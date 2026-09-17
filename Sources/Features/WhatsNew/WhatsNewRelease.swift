import Foundation
import SwiftUI

/// The copy behind the What's New screen, parsed from the `whats-new.md` bundled with the app.
///
/// The markdown file is the source of record, not this type: `Docs/whats-new.md` is a build
/// resource, so the release notes are edited as prose and rebuilt, with no Swift change and no
/// string literals to keep in step. See that file's own preamble for the format.
///
/// Parsing is **fail-closed** throughout — every `nil` below means "show no What's New screen at
/// all". A half-parsed screen shipped to customers is worse than a missing one, and the missing
/// one is caught by ``WhatsNewParsingTests``, which parses the shipped file on every CI run.
struct WhatsNewRelease: Equatable, Identifiable {
    /// The release these notes describe, e.g. `1.1.0`. Matched against the bundle's marketing
    /// version before anything is shown — see ``WhatsNewStore/shouldShow(release:currentVersion:lastSeen:)``.
    let version: String
    /// The screen's heading.
    let title: String
    /// The rows, in file order. Never empty: a release with no entries fails to parse.
    let entries: [WhatsNewEntry]

    var id: String { version }
}

/// One row: a tinted glyph, a short title, and a one-sentence blurb.
struct WhatsNewEntry: Equatable, Identifiable {
    let title: String
    let blurb: String
    /// An SF Symbol name, straight from the markdown's `Icon:` line. Validated against the system
    /// symbol set by ``WhatsNewParsingTests`` rather than at runtime — a typo would otherwise ship
    /// as an invisible glyph.
    let symbol: String
    let tint: WhatsNewTint

    var id: String { title }
}

/// The palette a `Tint:` line may name.
///
/// Deliberately a closed vocabulary of design-system roles rather than free hex: every case
/// resolves through ``BBColor``, so a row is correct in dark mode without the person writing the
/// copy thinking about it.
enum WhatsNewTint: String, CaseIterable {
    case brand, success, warning, danger, info
    case feeding, sleep, tummy, pumping, note

    var color: Color {
        switch self {
        case .brand: return BBColor.brand
        case .success: return BBColor.success
        case .warning: return BBColor.warning
        case .danger: return BBColor.danger
        case .info: return BBColor.info
        case .feeding: return BBColor.feeding
        case .sleep: return BBColor.sleep
        case .tummy: return BBColor.tummy
        case .pumping: return BBColor.pumping
        case .note: return BBColor.note
        }
    }
}

// MARK: - Parsing

extension WhatsNewRelease {
    /// The release notes shipped in this build, or `nil` if the resource is missing or malformed.
    ///
    /// Read once and cached: the file never changes within a launch, and the sheet's presentation
    /// check runs on every appearance of the tab bar.
    @MainActor
    static let bundled: WhatsNewRelease? = {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "md"),
              let markdown = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }
        return parse(markdown)
    }()

    /// The bundled file's name, without extension. `Docs/whats-new.md` flattens to this.
    static let resourceName = "whats-new"

    /// Parse the markdown format documented in `Docs/whats-new.md`.
    ///
    /// Three passes, in this order, because the format is designed so a human can write prose
    /// freely without tripping the parser:
    ///
    /// 1. A leading `---` fenced block carries the release-wide `version` and `title`.
    /// 2. Everything from there to the first `## ` heading is prose for whoever edits the file,
    ///    and is discarded — that is where the format's own instructions live.
    /// 3. Each `## ` heading opens a row: contiguous `Key: value` lines beneath it are its
    ///    fields, and the remaining prose is its blurb.
    ///
    /// Returns `nil` unless every part is present and well-formed.
    static func parse(_ markdown: String) -> WhatsNewRelease? {
        var lines = markdown.components(separatedBy: .newlines)[...]

        guard let frontMatter = takeFrontMatter(&lines),
              let version = frontMatter["version"], !version.isEmpty,
              let title = frontMatter["title"], !title.isEmpty
        else { return nil }

        // Discard the editor-facing prose: rows start at the first heading.
        let sections = splitSections(lines)
        let entries = sections.compactMap(parseEntry)
        // `compactMap` would silently drop a malformed row; a release is all-or-nothing, so a
        // single bad section takes the whole screen with it rather than shipping a gap.
        guard !entries.isEmpty, entries.count == sections.count else { return nil }

        return WhatsNewRelease(version: version, title: title, entries: entries)
    }

    /// Consume a leading `---` fenced block and return its `key: value` pairs, lowercased keys.
    /// `nil` when the file does not open with one.
    private static func takeFrontMatter(_ lines: inout ArraySlice<String>) -> [String: String]? {
        guard let first = lines.first, first.trimmed == "---" else { return nil }
        lines = lines.dropFirst()
        var pairs: [String: String] = [:]
        while let line = lines.first {
            lines = lines.dropFirst()
            if line.trimmed == "---" { return pairs }
            if let (key, value) = keyValue(line) { pairs[key] = value }
        }
        return nil // unterminated block
    }

    /// The lines under each `## ` heading, heading first. Anything before the first heading —
    /// the format's own documentation — is dropped.
    private static func splitSections(_ lines: ArraySlice<String>) -> [[String]] {
        var sections: [[String]] = []
        for line in lines {
            if line.hasPrefix("## ") {
                sections.append([line])
            } else if !sections.isEmpty {
                sections[sections.count - 1].append(line)
            }
        }
        return sections
    }

    /// One `## ` section into a row, or `nil` if it is missing a field.
    private static func parseEntry(_ section: [String]) -> WhatsNewEntry? {
        let title = String(section[0].dropFirst(3)).trimmed
        var symbol: String?
        var tint: WhatsNewTint?
        var blurbLines: [String] = []

        for line in section.dropFirst() {
            // Only the two known field names are fields; any other `Word: …` line is prose and
            // stays in the blurb. Treating every colon line as a field would silently swallow a
            // sentence that happens to start "Note: …", which is exactly the kind of thing copy
            // does and nobody would notice until it shipped.
            let field = keyValue(line)
            switch field?.key {
            case "icon":
                symbol = field?.value
            case "tint":
                tint = field.flatMap { WhatsNewTint(rawValue: $0.value.lowercased()) }
            default:
                if !line.trimmed.isEmpty { blurbLines.append(line.trimmed) }
            }
        }

        // Wrapped prose is one sentence to the reader, so rejoin it as one.
        let blurb = blurbLines.joined(separator: " ")
        guard !title.isEmpty, !blurb.isEmpty, let symbol, !symbol.isEmpty, let tint else { return nil }
        return WhatsNewEntry(title: title, blurb: blurb, symbol: symbol, tint: tint)
    }

    /// `Key: value` → `("key", "value")`, or `nil` when the line isn't one.
    ///
    /// The key must be a bare word so ordinary prose — a sentence with a colon in it, a markdown
    /// list item, a URL — is never mistaken for a field.
    private static func keyValue(_ line: String) -> (key: String, value: String)?  {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = String(line[line.startIndex..<colon]).trimmed
        guard !key.isEmpty, key.allSatisfy({ $0.isLetter }) else { return nil }
        let value = String(line[line.index(after: colon)...]).trimmed
        return value.isEmpty ? nil : (key.lowercased(), value)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}

import SwiftUI
import SwiftData

/// A reusable tag editor matching the Baby Buddy web app: selected tags render as removable
/// colored chips, typing autocompletes against the cached server tags (with their colors),
/// and an unmatched entry can be created inline. The binding is the list of tag *names*
/// (`[String]`) — exactly what the API and sync path expect on writes.
struct TagField: View {
    @Binding var selected: [String]
    @Query(sort: \CachedTag.lastUsed, order: .reverse) private var cached: [CachedTag]

    @State private var query = ""
    @FocusState private var fieldFocused: Bool

    private var allNames: [String] { cached.map(\.name) }

    private func color(for name: String) -> String? {
        cached.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.colorHex
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !selected.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(selected, id: \.self) { name in
                        TagChip(name: name, colorHex: color(for: name)) { remove(name) }
                    }
                }
            }

            TextField("Add a tag", text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .submitLabel(.done)
                .onSubmit(commitQuery)

            let suggestions = TagLogic.suggestions(query: query, all: allNames, selected: selected, limit: 8)
            let canCreate = TagLogic.canCreate(query: query, all: allNames, selected: selected)
            if !suggestions.isEmpty || canCreate {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { name in
                        Button { add(name) } label: {
                            TagChip(name: name, colorHex: color(for: name), removable: false)
                        }
                        .buttonStyle(.plain)
                    }
                    if canCreate {
                        Button { commitQuery() } label: {
                            Label("Add “\(query.trimmingCharacters(in: .whitespaces))”", systemImage: "plus")
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.tint.opacity(0.15), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .animation(.default, value: selected)
    }

    private func add(_ name: String) {
        selected = TagLogic.add(name, to: selected)
        query = ""
    }

    private func remove(_ name: String) {
        selected.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    private func commitQuery() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        add(trimmed)
    }
}

/// A single colored tag chip. Background uses the tag's server color (or a neutral default
/// for brand-new tags); the text color is the YIQ-complementary of the background, matching
/// Baby Buddy's web rendering.
struct TagChip: View {
    let name: String
    var colorHex: String?
    var removable: Bool = true
    /// Denser sizing for inline contexts like timeline rows.
    var compact: Bool = false
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 4) {
            Text(name).font((compact ? Font.caption2 : Font.caption).weight(.medium)).lineLimit(1)
            if removable {
                Button { onRemove?() } label: {
                    Image(systemName: "xmark.circle.fill").font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(TagColor.textColor(forHex: colorHex))
        .padding(.horizontal, compact ? 8 : 10).padding(.vertical, compact ? 2 : 5)
        .background(TagColor.color(forHex: colorHex), in: Capsule())
    }
}

// MARK: - Tag selection logic (pure, testable)

/// Pure helpers backing the picker: parsing/merging selections and computing suggestions.
/// Kept free of SwiftUI/SwiftData so they can be unit-tested directly.
enum TagLogic {
    /// Append a tag name to the selection, trimming whitespace and de-duplicating
    /// case-insensitively. Returns the selection unchanged for empty/duplicate input.
    static func add(_ raw: String, to selected: [String]) -> [String] {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return selected }
        guard !selected.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else {
            return selected
        }
        return selected + [name]
    }

    /// Cached tag names matching `query` (case-insensitive substring), excluding already
    /// selected ones. Prefix matches rank first, then alphabetical; capped at `limit`.
    static func suggestions(query: String, all: [String], selected: [String], limit: Int = 8) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let chosen = Set(selected.map { $0.lowercased() })
        let pool = all.filter { !chosen.contains($0.lowercased()) }
        let matches = q.isEmpty ? pool : pool.filter { $0.lowercased().contains(q) }
        let sorted = matches.sorted {
            let lp = $0.lowercased().hasPrefix(q), rp = $1.lowercased().hasPrefix(q)
            if lp != rp { return lp }
            return $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        return Array(sorted.prefix(limit))
    }

    /// Whether the trimmed query is a brand-new tag worth offering to create — non-empty and
    /// not an exact (case-insensitive) match of an existing or already-selected tag.
    static func canCreate(query: String, all: [String], selected: [String]) -> Bool {
        let name = query.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return false }
        let exists = (all + selected).contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        return !exists
    }
}

// MARK: - Tag colors

/// Translates Baby Buddy's `#RRGGBB` tag colors into SwiftUI colors, with a YIQ-based
/// complementary text color (the same heuristic the web app uses) and a neutral default
/// for tags that don't yet have a server-assigned color.
enum TagColor {
    /// Neutral chip color for brand-new tags before the server assigns one.
    static let defaultHex = "#9e9e9e"
    private static let darkText = Color(red: 0x10/255, green: 0x10/255, blue: 0x10/255)
    private static let lightText = Color(red: 0xEF/255, green: 0xEF/255, blue: 0xEF/255)

    static func color(forHex hex: String?) -> Color {
        Color(hex: hex ?? defaultHex) ?? Color(hex: defaultHex)!
    }

    /// Dark text on light backgrounds and vice versa, via YIQ luminance (threshold 128).
    static func textColor(forHex hex: String?) -> Color {
        guard let rgb = RGB(hex: hex ?? defaultHex) else { return lightText }
        let yiq = (rgb.r * 299 + rgb.g * 587 + rgb.b * 114) / 1000
        return yiq >= 128 ? darkText : lightText
    }
}

private struct RGB { let r, g, b: Int }

private extension RGB {
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let value = Int(s, radix: 16) else { return nil }
        self.init(r: (value >> 16) & 0xFF, g: (value >> 8) & 0xFF, b: value & 0xFF)
    }
}

extension Color {
    /// Initialize from a `#RRGGBB` (or `RRGGBB`) hex string; nil if malformed.
    init?(hex: String) {
        guard let rgb = RGB(hex: hex) else { return nil }
        self.init(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }
}

// MARK: - Flow layout

/// A simple wrapping layout that places subviews left-to-right, flowing to the next line
/// when the current row runs out of width. Used to lay out tag chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0, totalWidth: CGFloat = 0
        for size in subviews.map({ $0.sizeThatFits(.unspecified) }) {
            if rowWidth + size.width > maxWidth, rowWidth > 0 {
                totalHeight += rowHeight + spacing
                totalWidth = max(totalWidth, rowWidth - spacing)
                rowWidth = 0; rowHeight = 0
            }
            rowWidth += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        totalWidth = max(totalWidth, rowWidth - spacing)
        return CGSize(width: min(totalWidth, maxWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

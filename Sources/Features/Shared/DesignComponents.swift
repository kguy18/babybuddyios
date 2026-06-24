import SwiftUI

/// Reusable building blocks for the Baby Buddy design language: tinted glyph tiles, calm
/// rounded cards, metric tiles, event rows, the running-status dot, and the filled-button
/// styles that carry the action-color grammar. Built on the tokens in `BBColor`/`BBRadius`.

// MARK: Tinted glyph tile

/// A soft tinted square holding a record's custom glyph — the recurring motif across the app.
struct ActivityTile: View {
    @Environment(\.colorScheme) private var scheme
    let kind: EntityKind
    var size: CGFloat = 38
    var glyph: CGFloat = 20

    var body: some View {
        let color = BBColor.activity(kind)
        RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
            .fill(color.opacity(scheme == .dark ? 0.22 : 0.15))
            .frame(width: size, height: size)
            .overlay { kind.icon(glyph).foregroundStyle(color) }
    }
}

// MARK: Card container

/// White (elevated, in dark mode) card with generous rounding — the base surface.
struct BBCard<Content: View>: View {
    var cornerRadius: CGFloat = BBRadius.card
    var padding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BBColor.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

// MARK: Section header

/// Small uppercase section label (e.g. "Today", "Latest").
struct SectionHeader: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .kerning(0.4)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Running-status dot

/// A small "alive" indicator — a colored dot inside a faint matching halo.
struct RunningDot: View {
    var color: Color = BBColor.success

    var body: some View {
        ZStack {
            Circle().fill(color.opacity(0.2)).frame(width: 16, height: 16)
            Circle().fill(color).frame(width: 9, height: 9)
        }
    }
}

// MARK: Metric tile

/// A compact "today" stat: tinted glyph + label over a large tabular figure.
struct MetricTile: View {
    let kind: EntityKind
    let label: String
    let value: String

    var body: some View {
        BBCard(cornerRadius: BBRadius.tile, padding: 13) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    ActivityTile(kind: kind, size: 26, glyph: 16)
                    Text(label).font(.caption).foregroundStyle(.secondary)
                }
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
            }
        }
    }
}

// MARK: Event row

/// A single recent event: tinted tile, title + detail, and an absolute-over-relative time.
struct EventRow: View {
    let entity: LocalEntity

    var body: some View {
        BBCard(cornerRadius: BBRadius.row, padding: 13) {
            HStack(spacing: 12) {
                ActivityTile(kind: entity.kind, size: 40, glyph: 21)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entity.kind.displayName).font(.subheadline.weight(.semibold))
                    if let subtitle = EntityFormatting.subtitle(entity), !subtitle.isEmpty {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(entity.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                    Text(entity.timestamp, format: .relative(presentation: .named))
                        .font(.caption2).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: Inline tag chip

/// A neutral pill carrying a small colored dot — the inline tag treatment for timeline rows.
/// Deliberately distinct from the solid ``TagChip`` activity-style pill: the pill stays
/// neutral and only the dot uses the tag's server color (via `TagColor`).
struct TagDotChip: View {
    let name: String
    var colorHex: String?

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(TagColor.color(forHex: colorHex)).frame(width: 6, height: 6)
            Text(name).font(.caption2.weight(.medium)).lineLimit(1)
        }
        .foregroundStyle(BBColor.tagChipText)
        .padding(.leading, 7).padding(.trailing, 9).padding(.vertical, 3)
        .background(BBColor.tagChipFill, in: Capsule())
    }
}

// MARK: Buttons

/// Full-width filled button carrying the action-color grammar (stop=yellow, primary=blue…).
struct BBFilledButton: ButtonStyle {
    var background: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(foreground)
            .background(background, in: RoundedRectangle(cornerRadius: BBRadius.control, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

extension ButtonStyle where Self == BBFilledButton {
    /// Yellow "stop" button (action-color grammar).
    static var bbStop: BBFilledButton { BBFilledButton(background: BBColor.stop, foreground: Color(uiColor: UIColor(hex: "5C4300"))) }
    /// Blue primary / edit-convert button.
    static var bbPrimary: BBFilledButton { BBFilledButton(background: BBColor.primary, foreground: .white) }
}

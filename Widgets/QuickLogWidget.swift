import WidgetKit
import SwiftUI
import AppIntents

/// Home-screen widget: a stack of diaper tiles that each log a complete diaper change (Wet /
/// Solid / Wet + Solid) with one tap, via ``QuickLogIntent`` — no timer, no form. Static
/// content, so it's always useful. Mirrors ``QuickStartWidget``.
struct QuickLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BabyBuddyQuickLog", provider: QuickLogProvider()) { entry in
            QuickLogView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Quick log")
        .description("Log a diaper change or feeding with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickLogEntry: TimelineEntry {
    let date: Date
}

struct QuickLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry { QuickLogEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(QuickLogEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        completion(Timeline(entries: [QuickLogEntry(date: .now)], policy: .never))
    }
}

struct QuickLogView: View {
    let entry: QuickLogEntry

    /// The tiles shown, in order. Explicit (not `allCases`) so the widget's composition is
    /// deliberate: the three diaper actions first, then `quickFeed` as a distinct green tile —
    /// its feeding defaults are opt-in, so it's set apart from the diaper set rather than blended.
    private let actions: [QuickLogAction] = [.wetDiaper, .solidDiaper, .wetAndSolidDiaper, .quickFeed]

    var body: some View {
        panel
    }

    private var panel: some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                Text("Quick log")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 12))
                    .foregroundStyle(BBColor.brand)
            }
            VStack(spacing: 7) {
                ForEach(actions, id: \.self) { tile($0) }
            }
        }
    }

    private func tile(_ action: QuickLogAction) -> some View {
        let tint = action.tint
        return Button(intent: QuickLogIntent(action: action)) {
            HStack(spacing: 8) {
                Image(systemName: action.systemImage)
                    .font(.system(size: 15, weight: .semibold))
                Text(action.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
    }
}

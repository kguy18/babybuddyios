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
        .description("Log a diaper change with one tap.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct QuickLogEntry: TimelineEntry {
    let date: Date
    let isPremium: Bool
}

struct QuickLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry { QuickLogEntry(date: .now, isPremium: true) }

    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(QuickLogEntry(date: .now, isPremium: context.isPreview || SharedDefaults.isPremium))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        completion(Timeline(entries: [QuickLogEntry(date: .now, isPremium: SharedDefaults.isPremium)], policy: .never))
    }
}

struct QuickLogView: View {
    let entry: QuickLogEntry

    var body: some View {
        if entry.isPremium { panel } else { WidgetLockedView() }
    }

    private var panel: some View {
        VStack(spacing: 7) {
            HStack(spacing: 4) {
                Text("Log a change")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Image(systemName: EntityKind.change.systemImage)
                    .font(.system(size: 12))
                    .foregroundStyle(BBColor.activity(.change))
            }
            VStack(spacing: 7) {
                ForEach(QuickLogAction.allCases, id: \.self) { tile($0) }
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

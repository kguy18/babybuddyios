import WidgetKit
import SwiftUI

/// Widget extension entry point. This is intentionally a placeholder for Phase 0 — it stands
/// the extension up so the App Group + shared-store plumbing can be verified before any real
/// timer widgets land (Quick Start grid, Active Timer, etc.).
@main
struct BabyBuddyWidgets: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BabyBuddyPlaceholder", provider: PlaceholderProvider()) { _ in
            VStack(spacing: 6) {
                Image(systemName: "timer")
                    .font(.title2)
                    .foregroundStyle(Color(red: 0.216, green: 0.671, blue: 0.914)) // Baby Buddy #37abe9
                Text("Baby Buddy")
                    .font(.caption.weight(.medium))
            }
            .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Baby Buddy")
        .description("Timer widgets are coming soon.")
        .supportedFamilies([.systemSmall])
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry { PlaceholderEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        completion(Timeline(entries: [PlaceholderEntry(date: .now)], policy: .never))
    }
}

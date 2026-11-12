import WidgetKit
import SwiftUI
import AppIntents
import SwiftData

/// Home-screen actions in a two-by-two layout, with a short-lived receipt after a local save.
/// Each button logs one entry through ``QuickLogIntent`` without opening a form.
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
    var receipt: QuickLogReceipt? = nil
}

struct QuickLogProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickLogEntry { QuickLogEntry(date: .now) }

    func getSnapshot(in context: Context, completion: @escaping (QuickLogEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickLogEntry>) -> Void) {
        let entry = Self.currentEntry()
        var entries = [entry]
        if let receipt = entry.receipt { entries.append(QuickLogEntry(date: receipt.expiresAt)) }
        completion(Timeline(entries: entries, policy: .never))
    }

    private static func currentEntry() -> QuickLogEntry {
        let now = Date.now
        guard let container = try? ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: LocalStore.storeURL))
        else { return QuickLogEntry(date: now) }
        let context = ModelContext(container)
        return QuickLogEntry(date: now, receipt: QuickLogFeedback.visible(
            in: context, childID: SharedDefaults.selectedChildID, now: now))
    }
}

struct QuickLogView: View {
    let entry: QuickLogEntry
    @Environment(\.widgetFamily) private var family

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
                Text(entry.receipt == nil ? String(localized: "Quick log") : String(localized: "Saved on device"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Image(systemName: entry.receipt == nil ? "square.and.pencil" : "checkmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(BBColor.brand)
            }
            VStack(spacing: 8) {
                HStack(spacing: 8) { tile(actions[0]); tile(actions[1]) }
                HStack(spacing: 8) { tile(actions[2]); tile(actions[3]) }
            }
        }
    }

    private func tile(_ action: QuickLogAction) -> some View {
        let tint = action.tint
        let saved = entry.receipt?.action == action
        return Button(intent: QuickLogIntent(action: action)) {
            Group {
                if family == .systemSmall {
                    VStack(spacing: 2) {
                        Image(systemName: saved ? "checkmark.circle.fill" : action.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(action.title).font(.system(size: 11, weight: .medium))
                            .lineLimit(2).multilineTextAlignment(.center).minimumScaleFactor(0.8)
                    }
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: saved ? "checkmark.circle.fill" : action.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                        Text(action.title).font(.system(size: 13, weight: .medium)).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, family == .systemSmall ? 4 : 10)
            .frame(maxWidth: .infinity, minHeight: 44, maxHeight: .infinity)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(tint)
            .invalidatableContent()
        }
        .accessibilityLabel(saved ? String(localized: "\(action.title), saved on device") : action.title)
        .buttonStyle(.plain)
    }
}

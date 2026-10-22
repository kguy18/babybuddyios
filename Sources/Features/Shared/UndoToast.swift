import SwiftUI
import SwiftData

/// The one transient "Logged <kind> · Undo" toast. Every record created on this device lands
/// here via ``LocalRepository/didLogActivity``; showing a new one replaces the old (its window
/// to undo simply closes), and undo routes through the existing ``LocalRepository/delete`` —
/// an unpushed create is dropped locally, a synced one queues the normal delete. A change that
/// isn't a record, like ending sick mode, brings its own undo.
@MainActor @Observable
final class UndoToastCenter {
    static let shared = UndoToastCenter()

    /// Defaults key for the Settings toggle; absent means on.
    static let enabledKey = "undoToastEnabled"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    struct Item: Identifiable, Equatable {
        let id = UUID()
        /// The logged record, or `nil` when `revert` undoes something else.
        let localID: UUID?
        /// Draws the activity tile; `nil` for a toast about something that isn't a record.
        let kind: EntityKind?
        let title: String
        let subtitle: String?
        let revert: (@MainActor () -> Void)?
        /// A glyph in place of the activity tile, for a toast that isn't about a record.
        var symbol: String? = nil

        /// Whether there is anything to undo; a confirmation has no Undo.
        var canUndo: Bool { localID != nil || revert != nil }

        static func == (lhs: Item, rhs: Item) -> Bool { lhs.id == rhs.id }
    }

    private(set) var current: Item?
    /// How long a toast stays up. Injectable so tests don't wait; `BB_TOAST_SECONDS=<n>` (DEBUG)
    /// holds it open for screenshots.
    var duration: Duration = {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["BB_TOAST_SECONDS"], let n = Double(s) {
            return .seconds(n)
        }
        #endif
        return .seconds(5)
    }()
    private var dismissal: Task<Void, Never>?

    func show(_ entity: LocalEntity) {
        present(Item(localID: entity.localID, kind: entity.kind,
                     title: "Logged \(entity.kind.displayName.lowercased())",
                     subtitle: EntityFormatting.subtitle(entity), revert: nil))
    }

    /// A toast for a change that isn't a new record, with what undoing it does.
    func show(_ title: String, undo: @escaping @MainActor () -> Void) {
        present(Item(localID: nil, kind: nil, title: title, subtitle: nil, revert: undo))
    }

    /// A toast that only confirms something happened, with a check and no Undo.
    func confirm(_ title: String) {
        present(Item(localID: nil, kind: nil, title: title, subtitle: nil, revert: nil,
                     symbol: "checkmark.circle.fill"))
    }

    private func present(_ item: Item) {
        current = item
        dismissal?.cancel()
        dismissal = Task { [duration] in
            try? await Task.sleep(for: duration)
            if !Task.isCancelled, self.current == item { self.current = nil }
        }
    }

    func dismiss() {
        dismissal?.cancel()
        current = nil
    }

    /// Reverse the shown change. A create is looked up fresh: it may already be gone (deleted from
    /// the Timeline while the toast was up), in which case there is nothing to do.
    func undo(in context: ModelContext) {
        guard let item = current else { return }
        if let revert = item.revert {
            revert()
        } else if let localID = item.localID, let entity = LocalStore.fetch(localID: localID, in: context) {
            LocalRepository(context: context).delete(entity)
        }
        dismiss()
    }
}

/// The toast itself: activity tile, "Logged <kind>" plus the record's summary line, an Undo pill,
/// and a draining bar in the activity colour. Each screen that can create a record overlays it
/// (an overlay on the `TabView` itself renders but never receives taps on iOS 26).
struct UndoToastView: View {
    @Environment(\.modelContext) private var context
    @State private var center = UndoToastCenter.shared

    var body: some View {
        ZStack { toast }
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: center.current)
    }

    @ViewBuilder private var toast: some View {
        if let item = center.current {
            HStack(spacing: 11) {
                if let kind = item.kind {
                    ActivityTile(kind: kind, size: 34, glyph: 18)
                } else if let symbol = item.symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(BBColor.success)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.title)
                        .font(.subheadline.weight(.semibold))
                    if let subtitle = item.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                if item.canUndo {
                    Button {
                        center.undo(in: context)
                    } label: {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BBColor.brandAccent)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(BBColor.brandTint, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .background(alignment: .bottom) {
                DrainBar(color: item.kind.map(BBColor.activity) ?? BBColor.brand, duration: center.duration)
                    .id(item.id)
            }
            .background(BBColor.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 9, y: 4)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .accessibilityElement(children: .contain)
            .accessibilityLabel(item.kind.map { "Logged \($0.displayName)" } ?? item.title)
            .accessibilityActions {
                if item.canUndo { Button("Undo") { center.undo(in: context) } }
            }
        }
    }
}

/// A 3pt line that drains from full to empty over `duration` — the toast's visible countdown.
private struct DrainBar: View {
    let color: Color
    let duration: Duration
    @State private var fraction: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            Rectangle().fill(color)
                .frame(width: geo.size.width * fraction, height: 3)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onAppear {
            withAnimation(.linear(duration: Double(duration.components.seconds)
                                  + Double(duration.components.attoseconds) / 1e18)) {
                fraction = 0
            }
        }
    }
}

import SwiftUI

/// Settings ▸ Appearance ▸ Today tiles (#188): a switch per kind and drag handles to order the
/// tiles under TODAY on Home. The tiles that are on come first, in Home's order; the rest follow.
struct TodayTilesView: View {
    @AppStorage(TodayTiles.key, store: SharedDefaults.suite) private var raw: String?
    /// What the screen opened with, so leaving it reports only a real change.
    @State private var opened: [EntityKind]?

    private var enabled: [EntityKind] { TodayTiles.decode(raw) }
    private var rows: [EntityKind] { enabled + TodayTiles.eligible.filter { !enabled.contains($0) } }

    var body: some View {
        List {
            Section {
                ForEach(rows) { kind in
                    HStack(spacing: 12) {
                        ActivityTile(kind: kind, size: 30, glyph: 16)
                        Text(TodayTiles.label(kind)).font(.body)
                        Spacer(minLength: 8)
                        Toggle(TodayTiles.label(kind), isOn: isOn(kind))
                            .labelsHidden()
                            .tint(BBColor.primary)
                    }
                    .listRowBackground(BBColor.card)
                }
                .onMove { from, to in
                    var order = rows
                    order.move(fromOffsets: from, toOffset: to)
                    let on = Set(enabled)
                    raw = TodayTiles.encode(order.filter(on.contains))
                }
            } footer: {
                Text("Drag to change the order on Home. With every tile off, Home leaves out Today.")
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
        .background(BBColor.surface)
        .navigationTitle("Today Tiles")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if opened == nil { opened = enabled } }
        .onDisappear {
            if let opened, opened != enabled {
                Analytics.todayTilesChanged(enabled, isDefault: enabled == TodayTiles.defaults)
                self.opened = enabled
            }
        }
    }

    private func isOn(_ kind: EntityKind) -> Binding<Bool> {
        Binding(
            get: { enabled.contains(kind) },
            set: { on in
                var kinds = enabled.filter { $0 != kind }
                if on { kinds.append(kind) }
                raw = TodayTiles.encode(kinds)
            })
    }
}

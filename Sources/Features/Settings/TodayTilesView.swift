import SwiftUI

/// Settings ▸ Appearance ▸ Today tiles (#188): a switch per kind and drag handles to order the
/// tiles under TODAY on Home. The tiles that are on come first, in Home's order; the rest follow.
struct TodayTilesView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @AppStorage(TodayTiles.key, store: SharedDefaults.suite) private var raw: String?
    /// What the screen opened with, so leaving it reports only a real change.
    @State private var opened: [EntityKind]?

    private var enabled: [EntityKind] { TodayTiles.decode(raw) }
    private var rows: [EntityKind] { enabled + TodayTiles.eligible.filter { !enabled.contains($0) } }

    var body: some View {
        FoldSplitView {
            ScrollView {
                instructions
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } main: { split in
            tileList(showInstructions: !split)
        }
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

    private var instructions: Text {
        Text("Drag to change the order on Home. With every tile off, Home leaves out Today.")
    }

    private func tileList(showInstructions: Bool) -> some View {
        List {
            Section {
                ForEach(rows) { kind in
                    tileRow(kind)
                        .listRowBackground(BBColor.card)
                }
                .onMove { from, to in
                    var order = rows
                    order.move(fromOffsets: from, toOffset: to)
                    let on = Set(enabled)
                    raw = TodayTiles.encode(order.filter(on.contains))
                }
            } footer: {
                if showInstructions { instructions }
            }
        }
        .environment(\.editMode, .constant(.active))
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func tileRow(_ kind: EntityKind) -> some View {
        let label = TodayTiles.label(kind)
        let icon = ActivityTile(kind: kind, size: 30, glyph: 16)
        let name = Text(label).font(.body)
        let toggle = Toggle(label, isOn: isOn(kind))
            .labelsHidden()
            .tint(BBColor.primary)

        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                name.fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    icon
                    toggle
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 12) {
                icon
                name
                Spacer(minLength: 8)
                toggle
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

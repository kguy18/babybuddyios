import SwiftUI

/// Side-by-side "Mine vs Theirs" resolution for a single conflict, with whole-record
/// Keep Mine / Keep Theirs actions and a field-by-field merge.
struct ConflictResolutionView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss

    let conflict: ConflictRecord

    /// Per-field merge choices keyed by field name; true = keep mine.
    @State private var keepMineByField: [String: Bool] = [:]

    private var mine: [String: Any] { dict(conflict.localPayload) }
    private var theirs: [String: Any] { dict(conflict.serverPayload) }

    /// Fields that differ, excluding read-only/derived keys.
    private var differingFields: [String] {
        let ignored: Set<String> = ["id", "duration", "slug"]
        let keys = Set(mine.keys).union(theirs.keys).subtracting(ignored)
        return keys.filter { !valuesEqual(mine[$0], theirs[$0]) }.sorted()
    }

    var body: some View {
        Form {
            if conflict.serverDeleted {
                deletedSection
            } else {
                diffSection
                mergeSection
            }
            actionSection
        }
        .navigationTitle("Resolve Conflict")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            for field in differingFields where keepMineByField[field] == nil {
                keepMineByField[field] = true
            }
        }
    }

    // MARK: Sections

    private var deletedSection: some View {
        Section {
            Label("This \(conflict.kind.displayName.lowercased()) was deleted on the server "
                  + "while you had local changes.", systemImage: "trash")
            .font(.callout)
        }
    }

    private var diffSection: some View {
        Section("Differences") {
            ForEach(differingFields, id: \.self) { field in
                VStack(alignment: .leading, spacing: 4) {
                    Text(label(field)).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(alignment: .top) {
                        valueColumn("Mine", value: mine[field], highlight: .blue)
                        Divider()
                        valueColumn("Server", value: theirs[field], highlight: .green)
                    }
                }
            }
        }
    }

    private var mergeSection: some View {
        Section {
            ForEach(differingFields, id: \.self) { field in
                Picker(label(field), selection: bindingFor(field)) {
                    Text("Mine").tag(true)
                    Text("Server").tag(false)
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Text("Merge — pick per field")
        }
    }

    private var actionSection: some View {
        Section {
            Button("Keep Mine") { sync.resolveKeepMine(conflict); dismiss() }
            Button("Keep Server") { sync.resolveKeepTheirs(conflict); dismiss() }
            if !conflict.serverDeleted && !differingFields.isEmpty {
                Button("Save Merged") { saveMerged() }
            }
        }
    }

    // MARK: Helpers

    private func valueColumn(_ title: String, value: Any?, highlight: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(highlight)
            Text(display(value)).font(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func bindingFor(_ field: String) -> Binding<Bool> {
        Binding(get: { keepMineByField[field] ?? true },
                set: { keepMineByField[field] = $0 })
    }

    private func saveMerged() {
        var merged = theirs // start from server, overlay chosen-mine fields
        for field in differingFields where (keepMineByField[field] ?? true) {
            merged[field] = mine[field] ?? NSNull()
        }
        // Preserve identity + child.
        if let id = conflict.serverID { merged["id"] = id }
        guard let data = try? JSONSerialization.data(withJSONObject: merged) else { return }
        sync.resolveMerge(conflict, merged: data)
        dismiss()
    }

    private func label(_ field: String) -> String {
        field.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func display(_ value: Any?) -> String {
        switch value {
        case nil, is NSNull: return "—"
        case let b as Bool: return b ? "Yes" : "No"
        case let s as String: return s.isEmpty ? "—" : s
        case let arr as [Any]: return arr.isEmpty ? "—" : arr.map { "\($0)" }.joined(separator: ", ")
        case let n as NSNumber: return n.stringValue
        default: return "\(value!)"
        }
    }
}

// Shared JSON helpers for conflict views.
func dict(_ data: Data) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
}

func valuesEqual(_ a: Any?, _ b: Any?) -> Bool {
    // JSON values from JSONSerialization are NSObject subclasses (NSString/NSNumber/
    // NSNull/NSArray/NSDictionary) with correct deep `isEqual` semantics.
    let na = (a ?? NSNull()) as AnyObject
    return na.isEqual(b ?? NSNull())
}

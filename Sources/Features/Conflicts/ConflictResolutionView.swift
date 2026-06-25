import SwiftUI
import SwiftData

/// Resolve a single sync conflict in the Baby Buddy design language.
///
/// Three modes ride a `BBSegmentedControl` — the fast paths first, then Merge, which opens
/// the field-by-field diff. In Merge, only *differing* fields offer a choice (matching fields
/// resolve silently and are summarized in a quiet info row); Mine is brand-blue and Server is
/// neutral slate throughout, and the selected side gets a brand-blue ring + check badge.
///
/// Presentation only — the keep-mine / keep-server / merge resolution logic on `SyncEngine`
/// is unchanged; this view just restyles how the two sides are shown and picked.
struct ConflictResolutionView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let conflict: ConflictRecord

    /// Per-field merge choices keyed by field name; true = keep mine.
    @State private var keepMineByField: [String: Bool] = [:]
    @State private var mode: ResolveMode = .merge

    @Query private var cachedTags: [CachedTag]

    private enum ResolveMode: Hashable { case keepMine, keepServer, merge }

    private var mine: [String: Any] { dict(conflict.localPayload) }
    private var theirs: [String: Any] { dict(conflict.serverPayload) }

    /// Fields that differ, excluding read-only/derived keys.
    private var differingFields: [String] {
        let ignored: Set<String> = ["id", "duration", "slug"]
        let keys = Set(mine.keys).union(theirs.keys).subtracting(ignored)
        return keys.filter { !valuesEqual(mine[$0], theirs[$0]) }.sorted()
    }

    /// Modes offered for this conflict — Merge only appears when there's a diff to merge.
    private var modeOptions: [ResolveMode] {
        differingFields.isEmpty ? [.keepMine, .keepServer] : [.keepMine, .keepServer, .merge]
    }

    var body: some View {
        Group {
            if conflict.serverDeleted {
                deletedBody
            } else {
                mergeBody
            }
        }
        .background(BBColor.surface)
        .navigationTitle("Resolve Conflict")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            for field in differingFields where keepMineByField[field] == nil {
                keepMineByField[field] = true
            }
            if differingFields.isEmpty { mode = .keepMine }
        }
    }

    // MARK: Main (update-vs-update) body

    private var mergeBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard

                BBSegmentedControl(selection: $mode, options: modeOptions, label: title(for:))

                legend

                switch mode {
                case .merge:
                    diffControlsRow
                    VStack(spacing: 13) {
                        ForEach(differingFields, id: \.self) { fieldDiffRow($0) }
                    }
                    matchInfoRow
                case .keepMine, .keepServer:
                    outcomeCard
                    affectsLine
                }

                actionArea
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    // MARK: Server-deleted body

    private var deletedBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 17))
                        .foregroundStyle(BBColor.danger)
                    Text("This \(conflict.kind.displayName.lowercased()) was deleted on the server "
                         + "while you had local changes here. Keep your version to restore it, or "
                         + "discard it to accept the deletion.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(13)
                .background(BBColor.danger.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(spacing: 10) {
                    Button("Keep my version") { sync.resolveKeepMine(conflict); dismiss() }
                        .buttonStyle(.bbPrimary)
                    Button("Discard it") { sync.resolveKeepTheirs(conflict); dismiss() }
                        .buttonStyle(BBFilledButton(background: BBColor.danger, foreground: .white))
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
    }

    // MARK: Header

    private var headerCard: some View {
        BBCard(cornerRadius: BBRadius.tile, padding: 14) {
            HStack(spacing: 12) {
                ActivityTile(kind: conflict.kind, size: 40, glyph: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(conflict.kind.displayName) · \(recordTimeText)")
                        .font(.subheadline.weight(.semibold))
                    Text(conflict.serverDeleted
                         ? "Deleted on the server while you edited it"
                         : "Changed here and on the server")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                conflictPill
            }
        }
    }

    private var conflictPill: some View {
        HStack(spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text("Conflict").font(.caption.weight(.semibold))
        }
        .foregroundStyle(BBColor.restart)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(BBColor.restart.opacity(0.15), in: Capsule())
    }

    // MARK: Legend (Mine = brand blue · Server = neutral slate)

    private var legend: some View {
        HStack(spacing: 18) {
            legendItem(dot: BBColor.brand, name: "Mine", nameColor: BBColor.brandAccent, detail: mineDetail)
            legendItem(dot: .secondary, name: "Server", nameColor: BBColor.tagChipText, detail: serverDetail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 2)
    }

    private func legendItem(dot: Color, name: String, nameColor: Color, detail: String?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(name).font(.caption.weight(.semibold)).foregroundStyle(nameColor)
            if let detail {
                Text("· \(detail)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// When/how each side was edited — the local edit time (Mine) and when the server
    /// divergence was detected (Server). Both are real timestamps already on record.
    private var mineDetail: String? {
        LocalStore.fetch(localID: conflict.localID, in: modelContext)
            .map { $0.updatedAt.formatted(date: .omitted, time: .shortened) }
    }
    private var serverDetail: String? {
        conflict.detectedAt.formatted(date: .omitted, time: .shortened)
    }

    // MARK: Merge controls

    private var diffControlsRow: some View {
        HStack(spacing: 0) {
            Text(differingFields.count == 1 ? "1 field differs" : "\(differingFields.count) fields differ")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("All mine") { setAll(true) }
            Text(" · ").foregroundStyle(.tertiary)
            Button("All server") { setAll(false) }
        }
        .font(.subheadline.weight(.medium))
        .tint(BBColor.brandAccent)
        .padding(.horizontal, 2)
    }

    private func fieldDiffRow(_ field: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label(field))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BBColor.tagChipText)
            HStack(alignment: .top, spacing: 8) {
                choiceCard(field: field, keepMine: true)
                choiceCard(field: field, keepMine: false)
            }
        }
    }

    private func choiceCard(field: String, keepMine: Bool) -> some View {
        let value = keepMine ? mine[field] : theirs[field]
        let selected = (keepMineByField[field] ?? true) == keepMine
        return Button {
            withAnimation(.snappy(duration: 0.16)) { keepMineByField[field] = keepMine }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(keepMine ? "MINE" : "SERVER")
                    .font(.caption2.weight(.semibold))
                    .kerning(0.4)
                    .foregroundStyle(selected ? BBColor.brandAccent : .secondary)
                valueContent(field: field, value: value, selected: selected)
            }
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .padding(11)
            .background(selected ? BBColor.brandTint : BBColor.card,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? BBColor.primary : BBColor.fieldStroke,
                                  lineWidth: selected ? 1.5 : 1)
            }
            .overlay(alignment: .topTrailing) {
                if selected { checkBadge.padding(8) }
            }
        }
        .buttonStyle(.plain)
    }

    private var checkBadge: some View {
        Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 19, height: 19)
            .background(BBColor.primary, in: Circle())
    }

    @ViewBuilder
    private func valueContent(field: String, value: Any?, selected: Bool) -> some View {
        if field == "tags" {
            let names = tagNames(value)
            if names.isEmpty {
                Text("— none").font(.subheadline).foregroundStyle(.tertiary)
            } else {
                FlowLayout(spacing: 5) {
                    ForEach(names, id: \.self) { name in
                        TagDotChip(name: name, colorHex: tagColors[name.lowercased()])
                    }
                }
            }
        } else if isEmptyValue(value) {
            Text("— empty").font(.subheadline).foregroundStyle(.tertiary)
        } else {
            Text(displayValue(field, value))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(selected ? Color.primary : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Quiet summary of the fields that matched and were kept automatically.
    @ViewBuilder private var matchInfoRow: some View {
        if let summary = matchSummary {
            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 11)
            .background(BBColor.controlFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: Fast-path content

    private var outcomeCard: some View {
        let keepMine = mode == .keepMine
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: keepMine ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(keepMine ? BBColor.brandAccent : .secondary)
            Text(keepMine
                 ? "Keeps this device's version. The server's copy will be overwritten on the next sync."
                 : "Uses the server's version. Your local changes here will be replaced.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(keepMine ? BBColor.brandTint : BBColor.controlFill,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var affectsLine: some View {
        Text("Differs in \(listPhrase(differingFields.map(label))).")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 2)
    }

    // MARK: Action

    @ViewBuilder private var actionArea: some View {
        switch mode {
        case .merge:
            Button { saveMerged() } label: {
                Label("Save merged \(conflict.kind.displayName.lowercased())",
                      systemImage: "arrow.triangle.merge")
            }
            .buttonStyle(.bbPrimary)
            Text(tally)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        case .keepMine:
            Button("Keep my version") { sync.resolveKeepMine(conflict); dismiss() }
                .buttonStyle(.bbPrimary)
        case .keepServer:
            Button("Use server version") { sync.resolveKeepTheirs(conflict); dismiss() }
                .buttonStyle(.bbPrimary)
        }
    }

    private var tally: String {
        let mineCount = differingFields.filter { keepMineByField[$0] ?? true }.count
        let serverCount = differingFields.count - mineCount
        let mine = mineCount == 1 ? "1 field" : "\(mineCount) fields"
        return "\(mine) from this device · \(serverCount) from server"
    }

    // MARK: Actions

    private func setAll(_ keepMine: Bool) {
        withAnimation(.snappy(duration: 0.18)) {
            for field in differingFields { keepMineByField[field] = keepMine }
        }
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

    // MARK: Derived data

    /// Lowercased tag name → server `#RRGGBB` color, for tinting chips in tag diffs.
    private var tagColors: [String: String] {
        Dictionary(
            cachedTags.compactMap { tag in tag.colorHex.map { (tag.name.lowercased(), $0) } },
            uniquingKeysWith: { first, _ in first })
    }

    /// Meaningful fields present and equal on both sides — silently kept (skips identity keys
    /// and empty-equal values, which aren't worth surfacing).
    private var matchingFields: [String] {
        let identity: Set<String> = ["id", "child", "slug", "duration", "user", "url"]
        let shared = Set(mine.keys).intersection(theirs.keys).subtracting(identity)
        return shared.filter { key in
            guard valuesEqual(mine[key], theirs[key]) else { return false }
            return !isEmptyValue(mine[key])
        }.sorted { label($0) < label($1) }
    }

    private var matchSummary: String? {
        let labels = matchingFields.map(label)
        guard !labels.isEmpty else { return nil }
        if labels.count > 3 {
            return "\(labels.count) other fields match — kept automatically."
        }
        let verb = labels.count == 1 ? "matches" : "match"
        return "\(listPhrase(labels)) \(verb) — kept automatically."
    }

    private var recordTimeText: String {
        let ts = conflict.kind.timestamp(from: mine.isEmpty ? theirs : mine)
        guard ts != .distantPast else { return "—" }
        let time = ts.formatted(date: .omitted, time: .shortened)
        let cal = Calendar.current
        if cal.isDateInToday(ts) { return "Today, \(time)" }
        if cal.isDateInYesterday(ts) { return "Yesterday, \(time)" }
        return "\(ts.formatted(date: .abbreviated, time: .omitted)), \(time)"
    }

    // MARK: Formatting helpers

    private func title(for mode: ResolveMode) -> String {
        switch mode {
        case .keepMine: return "Keep mine"
        case .keepServer: return "Keep server"
        case .merge: return "Merge"
        }
    }

    private func tagNames(_ value: Any?) -> [String] {
        if let strings = value as? [String] { return strings }
        if let any = value as? [Any] { return any.compactMap { $0 as? String } }
        return []
    }

    private func isEmptyValue(_ value: Any?) -> Bool {
        switch value {
        case nil, is NSNull: return true
        case let s as String: return s.isEmpty
        case let arr as [Any]: return arr.isEmpty
        default: return false
        }
    }

    /// Joins labels into a natural list: "A", "A and B", "A, B and C".
    private func listPhrase(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return "\(items.dropLast().joined(separator: ", ")) and \(items.last!)"
        }
    }

    private func label(_ field: String) -> String {
        switch field {
        case "start": return "Start time"
        case "end": return "End time"
        case "time": return "Time"
        case "date": return "Date"
        case "amount": return "Amount"
        case "notes": return "Notes"
        case "note": return "Note"
        case "tags": return "Tags"
        case "type": return "Type"
        case "method": return "Method"
        case "color": return "Color"
        case "wet": return "Wet"
        case "solid": return "Solid"
        case "nap": return "Nap"
        case "milestone": return "Milestone"
        case "weight": return "Weight"
        case "height": return "Height"
        case "head_circumference": return "Head circumference"
        case "temperature": return "Temperature"
        case "bmi": return "BMI"
        case "name": return "Name"
        case "dosage": return "Dosage"
        case "dosage_unit": return "Dosage unit"
        default: return field.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Field-aware value text: times render as clock times, amount carries its unit; everything
    /// else falls back to the generic `display`.
    private func displayValue(_ field: String, _ value: Any?) -> String {
        switch field {
        case "start", "end", "time":
            if let s = value as? String, let d = APIDate.parse(s) {
                return d.formatted(date: .omitted, time: .shortened)
            }
        case "date":
            if let s = value as? String, let d = APIDate.parse(s) {
                return d.formatted(date: .abbreviated, time: .omitted)
            }
        case "amount":
            if let n = value as? NSNumber { return EntityFormatting.formatAmount(n.doubleValue) }
        default:
            break
        }
        return display(value)
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

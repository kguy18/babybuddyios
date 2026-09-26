import SwiftUI
import UIKit

/// One editable name and value pair. Its own type so `ForEach` can tell rows apart while one is
/// removed; ``CustomHeader`` is what gets validated and stored.
struct HeaderRow: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var value = ""
    /// Set for a header the app knows, such as a Cloudflare service token's: the row shows a plain
    /// label in place of an editable name.
    var preset: Preset?

    struct Preset: Equatable {
        let label: String
        let placeholder: String
        let secret: Bool
    }

    var header: CustomHeader { CustomHeader(name: name, value: value) }

    init(name: String = "", value: String = "", preset: Preset? = nil) {
        self.name = name
        self.value = value
        self.preset = preset
    }

    /// A saved header, labelled when it's one the app knows.
    init(_ header: CustomHeader) {
        self.init(name: header.name, value: header.value, preset: Self.presets[header.name.lowercased()])
    }

    /// The two headers a Cloudflare Access service token is sent as.
    static func cloudflareServiceToken() -> [HeaderRow] {
        ["CF-Access-Client-Id", "CF-Access-Client-Secret"].map { HeaderRow(CustomHeader(name: $0, value: "")) }
    }

    private static let presets: [String: Preset] = [
        "cf-access-client-id": Preset(label: "Client ID", placeholder: "Ends in .access", secret: false),
        "cf-access-client-secret": Preset(label: "Client Secret", placeholder: "Paste the secret", secret: true),
    ]
}

/// The custom header rows, shared by sign-in and Settings. A known header shows its label and a
/// value field; any other shows a name field and a secure value field. Every value has Paste, since
/// these are long secrets copied from somewhere else.
struct CustomHeaderFields: View {
    @Binding var rows: [HeaderRow]
    var addTitle = "Add header"

    /// Return moves through the fields in order (Client ID, then Client Secret) and closes the
    /// keyboard after the last one.
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case name(UUID), value(UUID)
    }

    /// The fields in the order Return walks them: a preset row has only its value.
    private var order: [Field] {
        rows.flatMap { $0.preset == nil ? [Field.name($0.id), .value($0.id)] : [.value($0.id)] }
    }

    private func advance(from field: Field) {
        guard let index = order.firstIndex(of: field), index + 1 < order.count else {
            focus = nil
            return
        }
        focus = order[index + 1]
    }

    private func isLast(_ field: Field) -> Bool { order.last == field }

    var body: some View {
        VStack(spacing: 0) {
            ForEach($rows) { $row in
                Group {
                    if let preset = row.preset {
                        presetRow(preset, $row)
                    } else {
                        editableRow($row)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.vertical, 13)
                Rectangle().fill(BBColor.divider).frame(height: 1).padding(.leading, 15)
            }
            Button {
                rows.append(HeaderRow())
            } label: {
                Label(addTitle, systemImage: "plus.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BBColor.brandAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 13)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func presetRow(_ preset: HeaderRow.Preset, _ row: Binding<HeaderRow>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(preset.label).font(.subheadline.weight(.semibold))
                Spacer(minLength: 8)
                Text(row.wrappedValue.name)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                removeButton(row.wrappedValue)
            }
            HStack(spacing: 8) {
                Group {
                    if preset.secret {
                        SecureField(preset.placeholder, text: row.value)
                    } else {
                        TextField(preset.placeholder, text: row.value)
                    }
                }
                .font(.system(size: 17))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(preset.label)
                .focused($focus, equals: .value(row.wrappedValue.id))
                .submitLabel(isLast(.value(row.wrappedValue.id)) ? .done : .next)
                .onSubmit { advance(from: .value(row.wrappedValue.id)) }
                pasteButton(into: row.value)
            }
        }
    }

    private func editableRow(_ row: Binding<HeaderRow>) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 10) {
                TextField("Header name", text: row.name)
                    .font(.system(size: 16).monospaced())
                    .focused($focus, equals: .name(row.wrappedValue.id))
                    .submitLabel(.next)
                    .onSubmit { advance(from: .name(row.wrappedValue.id)) }
                HStack(spacing: 8) {
                    SecureField("Header value", text: row.value)
                        .font(.system(size: 17))
                        .focused($focus, equals: .value(row.wrappedValue.id))
                        .submitLabel(isLast(.value(row.wrappedValue.id)) ? .done : .next)
                        .onSubmit { advance(from: .value(row.wrappedValue.id)) }
                    pasteButton(into: row.value)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            removeButton(row.wrappedValue)
        }
    }

    private func removeButton(_ row: HeaderRow) -> some View {
        Button {
            rows.removeAll { $0.id == row.id }
        } label: {
            Image(systemName: "minus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(BBColor.danger)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Remove header")
    }

    private func pasteButton(into value: Binding<String>) -> some View {
        Button {
            if let clip = UIPasteboard.general.string {
                value.wrappedValue = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BBColor.brandAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BBColor.brandTint, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    static let footnote = "Sent with every request to your server, never to another address."
}

/// Sign-in's Advanced configuration. After a gate that headers can get through answered, it shows
/// where sign-in stopped and how to fix it, then the path the next try will take once the headers
/// are filled in. Edits stay in the sheet until Save; Cancel drops them.
struct AdvancedConfigurationSheet: View {
    let gate: AccessGate?
    let host: String
    /// The saved rows, and whether sign-in should run again once the sheet has closed.
    let onSave: ([HeaderRow], Bool) -> Void

    @State private var draft: [HeaderRow]
    @Environment(\.dismiss) private var dismiss

    init(rows: [HeaderRow], gate: AccessGate?, host: String, onSave: @escaping ([HeaderRow], Bool) -> Void) {
        self.gate = gate.flatMap { $0.acceptsHeaders ? $0 : nil }
        self.host = host
        self.onSave = onSave
        _draft = State(initialValue: rows)
    }

    /// Every row has a name and a value, so the next try will send them all.
    private var ready: Bool {
        !draft.isEmpty && draft.allSatisfy {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty
                && !$0.value.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let gate {
                        SignInTrace(gate: gate, host: host, ready: ready)
                        if !ready { fixBox(gate) }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(gate == .cloudflareAccess ? "Service token" : "Custom headers")
                            .padding(.horizontal, 4)
                        BBCard(cornerRadius: BBRadius.tile, padding: 0) {
                            CustomHeaderFields(rows: $draft, addTitle: draft.isEmpty ? "Add header" : "Add another header")
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .background(BBColor.surface.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { footer }
            .navigationTitle("Advanced configuration")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                // Cloudflare Access always takes the same two headers, so an empty set starts with
                // them. Here rather than in `init`: a sheet's content can be built before it opens,
                // and `@State` keeps the value from the first build.
                if gate == .cloudflareAccess, draft.isEmpty { draft = HeaderRow.cloudflareServiceToken() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button {
                onSave(draft, gate != nil)
                dismiss()
            } label: {
                Label(gate == nil ? "Save" : "Save and try again",
                      systemImage: gate == nil ? "checkmark" : "arrow.clockwise")
            }
            .buttonStyle(.bbPrimary)
            .disabled(gate != nil && !ready)
            .opacity(gate != nil && !ready ? 0.5 : 1)
            Text(CustomHeaderFields.footnote)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(BBColor.surface)
        .overlay(alignment: .top) { Rectangle().fill(BBColor.fieldStroke).frame(height: 1) }
    }

    private func fixBox(_ gate: AccessGate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(gate == .cloudflareAccess ? "Get through with a service token" : "If it checks a header",
                  systemImage: "wrench.and.screwdriver.fill")
                .font(.headline)
                .foregroundStyle(BBColor.brandAccent)
            let steps = Self.steps(for: gate, host: host)
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    if steps.count > 1 {
                        Text("\(index + 1)")
                            .font(.footnote.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(BBColor.brandAccent, in: Circle())
                            .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
                    }
                    Text(LocalizedStringKey(step))
                        .font(.callout)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BBColor.brandTint, in: RoundedRectangle(cornerRadius: BBRadius.tile, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: BBRadius.tile, style: .continuous)
                .strokeBorder(BBColor.brandAccent.opacity(0.25), lineWidth: 1)
        }
    }

    /// Markdown, for the bold terms that match what the person looks for in Cloudflare's dashboard.
    static func steps(for gate: AccessGate, host: String) -> [String] {
        switch gate {
        case .cloudflareAccess:
            return [
                "In Cloudflare Zero Trust, create a **service token**. Copy the Client ID and Client Secret. The secret is shown only once.",
                "In the Access application for **\(host)**, add a policy with the **Service Auth** action for that token.",
                "Paste the Client ID and Client Secret below.",
            ]
        default:
            return ["Add the headers it checks below. If it's a login proxy such as Authentik or Authelia, let /api/ and /media/ through it instead."]
        }
    }
}

/// The path sign-in took: where it stopped, or, once the headers are filled in, the way the next try
/// will get through.
struct SignInTrace: View {
    let gate: AccessGate
    let host: String
    let ready: Bool

    struct Hop: Equatable {
        enum Kind { case plain, stopped, gate, arrived }
        let symbol: String
        let title: String
        let detail: String
        let kind: Kind
    }

    static func hops(for gate: AccessGate, host: String, ready: Bool) -> [Hop] {
        let app = Hop(symbol: "iphone", title: "This app",
                      detail: ready ? (gate == .cloudflareAccess ? "Sends the service token" : "Sends the custom headers")
                                    : "Asked for the Baby Buddy API",
                      kind: .plain)
        let gateName = gate == .cloudflareAccess ? "Cloudflare Access" : "The gate in front of \(host)"
        if ready {
            return [app,
                    Hop(symbol: "shield.lefthalf.filled", title: gateName,
                        detail: gate == .cloudflareAccess ? "Checks the token and lets the app through"
                                                          : "Checks the headers and lets the app through",
                        kind: .gate),
                    Hop(symbol: "server.rack", title: "Baby Buddy", detail: host, kind: .arrived)]
        }
        if gate == .cloudflareAccess {
            return [app,
                    Hop(symbol: "server.rack", title: host, detail: "Sent the app to Cloudflare", kind: .plain),
                    Hop(symbol: "cloud", title: "Cloudflare Access", detail: "Its sign-in page", kind: .stopped)]
        }
        return [app, Hop(symbol: "shield.lefthalf.filled", title: gateName,
                         detail: "Answered with a web page, not the API", kind: .stopped)]
    }

    var body: some View {
        let title = ready ? "On the next try" : "Where sign-in stopped"
        let tint = ready ? BBColor.successAccent : BBColor.warningAccent
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption.weight(.bold))
                .kerning(0.6)
                .foregroundStyle(tint)
                .padding(.bottom, 6)
            let hops = Self.hops(for: gate, host: host, ready: ready)
            ForEach(Array(hops.enumerated()), id: \.offset) { index, hop in
                if index > 0 {
                    Image(systemName: "arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.leading, 12)
                        .accessibilityHidden(true)
                }
                hopRow(hop)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BBColor.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(ready ? BBColor.success.opacity(0.45) : BBColor.warning.opacity(0.7), lineWidth: 1.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func hopRow(_ hop: Hop) -> some View {
        let tint: Color = switch hop.kind {
        case .plain: .secondary
        case .stopped: BBColor.danger
        case .gate: BBColor.brandAccent
        case .arrived: BBColor.success
        }
        return HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(hop.kind == .plain ? BBColor.controlFill : tint.opacity(0.14))
                .frame(width: 38, height: 38)
                .overlay {
                    Image(systemName: hop.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(tint)
                }
            VStack(alignment: .leading, spacing: 1) {
                Text(hop.title).font(.body.weight(.semibold)).lineLimit(1)
                Text(hop.detail).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if hop.kind == .stopped {
                Text("Stopped here")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(BBColor.danger)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(BBColor.danger.opacity(0.12), in: Capsule())
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Settings ▸ Server ▸ Custom headers. Saving runs the same probe as sign-in, and a failed probe
/// keeps the old headers.
struct CustomHeadersView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [HeaderRow] = []
    @State private var isSaving = false
    @State private var error: String?

    private var saved: [CustomHeader] { session.config?.headers ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                BBCard(cornerRadius: BBRadius.tile, padding: 0) {
                    CustomHeaderFields(rows: $rows)
                }
                if let error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(BBColor.danger)
                        .padding(.horizontal, 4)
                }
                Text("Only for a server behind an access gate that checks a header. \(CustomHeaderFields.footnote)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(BBColor.surface.ignoresSafeArea())
        .navigationTitle("Custom headers")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { save() }
                        .disabled(rows.map(\.header) == saved)
                }
            }
        }
        .onAppear { rows = saved.map(HeaderRow.init) }
    }

    private func save() {
        isSaving = true
        error = nil
        Task {
            if await session.updateHeaders(rows.map(\.header)) {
                dismiss()
            } else {
                error = session.lastError
                session.lastError = nil // or onboarding shows it after a later sign-out
            }
            isSaving = false
        }
    }
}

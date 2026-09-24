import SwiftUI

/// One editable name and value pair. Its own type so `ForEach` can tell rows apart while one is
/// removed; ``CustomHeader`` is what gets validated and stored.
struct HeaderRow: Identifiable, Equatable {
    let id = UUID()
    var name = ""
    var value = ""

    var header: CustomHeader { CustomHeader(name: name, value: value) }
}

/// The custom header rows, shared by sign-in and Settings: a name field and a secure value field per
/// row, a remove button on each, and "Add header" below.
struct CustomHeaderFields: View {
    @Binding var rows: [HeaderRow]

    var body: some View {
        VStack(spacing: 0) {
            ForEach($rows) { $row in
                HStack(spacing: 10) {
                    VStack(spacing: 8) {
                        TextField("Header name", text: $row.name)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        SecureField("Header value", text: $row.value)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                    .font(.system(size: 15))
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
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                Rectangle().fill(BBColor.divider).frame(height: 1)
            }
            Button {
                rows.append(HeaderRow())
            } label: {
                Label("Add header", systemImage: "plus.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BBColor.brandAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    static let footnote = "Only for a server behind an access gate that checks a header. The app sends these with every request to your server."
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
                Text(CustomHeaderFields.footnote)
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
        .onAppear { rows = saved.map { HeaderRow(name: $0.name, value: $0.value) } }
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

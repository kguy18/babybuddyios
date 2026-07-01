import SwiftUI
import SwiftData
import PhotosUI

/// Server/account, offline-first sync status, app lock, and sign-out — styled to the Baby
/// Buddy design system: a child-profile masthead over grouped white ``BBCard`` sections, each
/// row carrying a small tinted glyph tile (server=blue, sync=cyan, conflicts=orange, lock=indigo),
/// brand-blue toggles, and the lone destructive sign-out kept in its own card.
struct SettingsView: View {
    @Environment(AppSession.self) private var session
    @Environment(SyncEngine.self) private var sync
    @Environment(AppLockManager.self) private var lock
    @Environment(\.modelContext) private var context

    @State private var photoItem: PhotosPickerItem?

    @Query(filter: #Predicate<LocalEntity> { $0.kindRaw == "child" }, sort: \.timestamp)
    private var children: [LocalEntity]
    @Query private var pendingMutations: [PendingMutation]
    @Query private var conflicts: [ConflictRecord]

    // Shared with the Dashboard/Timeline tabs and the widget, so "Switch" here moves them too.
    @AppStorage("selectedChildID", store: SharedDefaults.suite) private var selectedChildID = 0

    @State private var debugConflict: ConflictRecord?
    @State private var debugIcons = false
    @State private var showingPending = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    masthead

                    if case .authenticated(let config) = session.state {
                        sectioned("Server") { serverCard(config) }
                    }

                    sectioned("Sync") { syncCard }

                    sectioned("Security") {
                        securityCard
                        Text(lock.biometryAvailable
                             ? "Locks the app when reopened after being in the background."
                             : "Set up Face ID, Touch ID, or a device passcode to enable app lock.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }

                    signOutCard.padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(BBColor.surface)
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPending) { PendingChangesView() }
            .sheet(item: $debugConflict) { c in
                NavigationStack { ConflictResolutionView(conflict: c) }
            }
            .sheet(isPresented: $debugIcons) {
                #if DEBUG
                NavigationStack { IconGalleryView() }
                #endif
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.environment["BB_OPEN_CONFLICT"] == "1" {
                    debugConflict = conflicts.first
                }
                if ProcessInfo.processInfo.environment["BB_ICONS"] == "1" {
                    debugIcons = true
                }
                #endif
            }
        }
    }

    // MARK: Masthead

    /// Child-profile card: avatar + name + age, with a "Switch" affordance when there's more
    /// than one child (reuses the shared `selectedChildID` so every tab follows the choice).
    private var masthead: some View {
        BBCard(cornerRadius: BBRadius.tile, padding: 14) {
            HStack(spacing: 13) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    ChildAvatar(
                        pictureURL: currentChild?.payloadObject["picture"] as? String,
                        initial: avatarInitial, size: 48)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(4)
                            .background(BBColor.primary, in: Circle())
                            .overlay(Circle().stroke(BBColor.card, lineWidth: 1.5))
                    }
                }
                .disabled(currentChild == nil)
                .onChange(of: photoItem) { _, item in loadChildPhoto(item) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(childDisplayName).font(.system(size: 17, weight: .semibold))
                    if let subtitle = childSubtitle {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                switchControl
            }
        }
    }

    @ViewBuilder private var switchControl: some View {
        if children.count > 1 {
            Menu {
                ForEach(children, id: \.serverID) { child in
                    Button {
                        if let id = child.serverID { selectedChildID = id }
                    } label: {
                        Label(fullName(child), systemImage: child.serverID == selectedChildID
                              ? "checkmark" : "person.crop.circle")
                    }
                }
            } label: {
                Text("Switch")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BBColor.brandAccent)
            }
        }
    }

    // MARK: Server

    private func serverCard(_ config: ServerConfig) -> some View {
        card {
            SettingsRow(symbol: "cloud", tint: BBColor.brand,
                        glyphColor: BBColor.brandAccent, title: "Server") {
                HStack(spacing: 6) {
                    Circle().fill(BBColor.success).frame(width: 7, height: 7)
                    Text(config.baseURL.host() ?? config.baseURL.absoluteString)
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    // MARK: Sync

    /// The offline-first truth: when we last synced, how many writes are queued, and any
    /// conflicts waiting to be resolved.
    private var syncCard: some View {
        card {
            Button { Task { await sync.sync() } } label: {
                SettingsRow(symbol: "arrow.triangle.2.circlepath", tint: BBColor.info,
                            title: "Sync now") { syncTrailing }
            }
            .buttonStyle(.plain)
            .disabled(sync.status == .syncing)

            rowDivider

            pendingRow

            rowDivider

            conflictRow
        }
    }

    /// Pending writes open the queue when any exist; otherwise the row reads "All synced".
    @ViewBuilder private var pendingRow: some View {
        if pendingMutations.isEmpty {
            SettingsRow(symbol: "checkmark.icloud", tint: BBColor.success, title: "Pending changes") {
                Text("All synced")
                    .font(.subheadline.weight(.medium)).foregroundStyle(BBColor.success)
            }
        } else {
            Button { showingPending = true } label: {
                SettingsRow(symbol: "icloud.and.arrow.up", tint: BBColor.warning, title: "Pending changes") {
                    HStack(spacing: 4) {
                        Text("\(pendingMutations.count) queued")
                            .font(.subheadline.weight(.medium)).foregroundStyle(BBColor.warning)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var syncTrailing: some View {
        switch sync.status {
        case .syncing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Syncing…").font(.subheadline).foregroundStyle(.secondary)
            }
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(BBColor.danger).lineLimit(1)
        case .idle:
            if let last = sync.lastSyncDate {
                Text(last.formatted(.relative(presentation: .named)))
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Never").font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    /// Conflicts surface the resolution inbox when any exist; otherwise the row reads "All clear".
    @ViewBuilder private var conflictRow: some View {
        if conflicts.isEmpty {
            SettingsRow(symbol: "arrow.triangle.merge", tint: BBColor.restart, title: "Conflicts") {
                Text("All clear").font(.subheadline).foregroundStyle(.secondary)
            }
        } else {
            NavigationLink {
                ConflictInboxView()
            } label: {
                SettingsRow(symbol: "arrow.triangle.merge", tint: BBColor.restart, title: "Conflicts") {
                    HStack(spacing: 4) {
                        Text("\(conflicts.count) to resolve")
                            .font(.subheadline.weight(.medium)).foregroundStyle(BBColor.restart)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Security

    private var securityCard: some View {
        card {
            SettingsRow(symbol: "faceid", tint: BBColor.sleep, title: "Require Face ID") {
                Toggle("", isOn: Binding(
                    get: { lock.isEnabled },
                    set: { lock.isEnabled = $0 }))
                    .labelsHidden()
                    .tint(BBColor.primary)
                    .disabled(!lock.biometryAvailable)
            }
        }
    }

    // MARK: Sign out

    private var signOutCard: some View {
        Button { session.signOut() } label: {
            BBCard(cornerRadius: BBRadius.tile, padding: 14) {
                HStack(spacing: 7) {
                    Spacer()
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Sign out").font(.system(size: 16, weight: .semibold))
                    Spacer()
                }
                .foregroundStyle(BBColor.danger)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Layout helpers

    private func sectioned<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            content()
        }
    }

    /// A grouped card of settings rows: zero outer padding, rows inset to the mockup's 15pt.
    private func card<V: View>(@ViewBuilder _ content: @escaping () -> V) -> some View {
        BBCard(cornerRadius: BBRadius.tile, padding: 0) {
            VStack(spacing: 0) { content() }
                .padding(.horizontal, 15)
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(BBColor.divider).frame(height: 0.5)
    }

    // MARK: Child derivation

    private var currentChild: LocalEntity? {
        children.first { $0.serverID == selectedChildID } ?? children.first
    }

    /// Decode the picked photo, attach it to the selected child (immediate `file://` preview), and
    /// enqueue the upload. Children are already synced, so the sync drain PATCHes it right away.
    private func loadChildPhoto(_ item: PhotosPickerItem?) {
        guard let item, let child = currentChild else { return }
        Task {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            LocalRepository(context: context).enqueueImageUpload(
                for: child, imageData: image.bbUploadJPEG() ?? data)
            await sync.sync()
        }
    }

    private var childDisplayName: String {
        currentChild.map(firstName) ?? "Baby Buddy"
    }

    private var avatarInitial: String {
        String(childDisplayName.prefix(1)).uppercased()
    }

    private var childSubtitle: String? {
        guard let child = currentChild,
              let raw = child.payloadObject["birth_date"] as? String,
              let birth = APIDate.parse(raw) else { return nil }
        let born = birth.formatted(.dateTime.month(.abbreviated).day())
        return "Born \(born) · \(ageString(birth))"
    }

    private func firstName(_ entity: LocalEntity) -> String {
        let p = entity.payloadObject
        let first = (p["first_name"] as? String) ?? ""
        let last = (p["last_name"] as? String) ?? ""
        if !first.isEmpty { return first }
        return last.isEmpty ? "Child" : last
    }

    private func fullName(_ entity: LocalEntity) -> String {
        let p = entity.payloadObject
        let first = (p["first_name"] as? String) ?? ""
        let last = (p["last_name"] as? String) ?? ""
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Child" : name
    }

    /// A friendly age: years for ≥2y, otherwise months, then weeks, then days.
    private func ageString(_ birth: Date) -> String {
        let cal = Calendar.current
        let now = Date()
        let comps = cal.dateComponents([.year, .month], from: birth, to: now)
        let years = comps.year ?? 0
        if years >= 2 { return "\(years) years" }
        let months = years * 12 + (comps.month ?? 0)
        if months >= 1 { return months == 1 ? "1 month" : "\(months) months" }
        let days = cal.dateComponents([.day], from: birth, to: now).day ?? 0
        let weeks = days / 7
        if weeks >= 1 { return weeks == 1 ? "1 week" : "\(weeks) weeks" }
        return days <= 1 ? "Newborn" : "\(days) days"
    }
}

// MARK: - Settings row

/// One grouped-settings row: a small tinted glyph tile, a title, and trailing content
/// (a value, a status, a toggle, or a chevron). Mirrors ``ActivityTile``'s tint wash.
private struct SettingsRow<Trailing: View>: View {
    @Environment(\.colorScheme) private var scheme
    let symbol: String
    let tint: Color
    var glyphColor: Color? = nil
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(tint.opacity(scheme == .dark ? 0.22 : 0.15))
                .frame(width: 30, height: 30)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(glyphColor ?? tint)
                }
            Text(title).font(.system(size: 16))
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

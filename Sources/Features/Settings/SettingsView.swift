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
    @Environment(PurchaseManager.self) private var purchases
    @Environment(LiveActivityManager.self) private var liveActivity
    @Environment(AppIconManager.self) private var icons
    @Environment(\.modelContext) private var context

    @State private var photoItem: PhotosPickerItem?

    @Query(filter: #Predicate<LocalEntity> { $0.kindRaw == "child" }, sort: \.timestamp)
    private var children: [LocalEntity]
    @Query private var pendingMutations: [PendingMutation]
    @Query private var conflicts: [ConflictRecord]

    // Shared with the Dashboard/Timeline tabs and the widget, so "Switch" here moves them too.
    @AppStorage("selectedChildID", store: SharedDefaults.suite) private var selectedChildID = 0
    // Mirrors SharedDefaults.liveActivitiesEnabled; keep the key and default in sync.
    @AppStorage("liveActivitiesEnabled", store: SharedDefaults.suite) private var liveActivitiesEnabled = true
    // Mirror SharedDefaults.quickFeedType/Method — the Quick Log widget's one-tap Feeding
    // defaults, read by the widget's intent. Keep the keys and defaults in sync.
    @AppStorage("quickFeedType", store: SharedDefaults.suite) private var quickFeedType: FeedingType = .breastMilk
    @AppStorage("quickFeedMethod", store: SharedDefaults.suite) private var quickFeedMethod: FeedingMethod = .bothBreasts
    // The support-nudge switch. App-only defaults, not the App Group — nudges are an app-process
    // concern; the key comes from ``SupportNudgeStore`` so the two can't drift apart.
    @AppStorage(SupportNudgeStore.remindersEnabledKey) private var supportRemindersEnabled = true

    @State private var debugConflict: ConflictRecord?
    @State private var debugIcons = false
    @State private var showingAppIcons = false
    @State private var showingPending = false
    @State private var showingAcknowledgements = false
    @State private var showingSupporter = false
    /// Whether a nudge has been shown yet, which is what reveals the "Support reminders" switch.
    /// Refreshed on appear rather than observed: nudges only ever fire from the Dashboard, so this
    /// tab is re-entered after any change.
    @State private var hasSeenNudge = false

    // Contact Support: the row offers to attach diagnostics, then presents the mail composer
    // (or falls back to a mailto: link when no Mail account is set up).
    @State private var showingContactOptions = false
    @State private var mailPayload: MailPayload?
    @State private var showingMailUnavailable = false
    @Environment(\.openURL) private var openURL

    /// Wraps the seeded email body so `.sheet(item:)` has an `Identifiable` to present.
    private struct MailPayload: Identifiable {
        let id = UUID()
        let body: String
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    masthead

                    sectioned("Support the app") {
                        supporterCard
                        Text("Everything in the app is free. Supporting is optional and helps fund development.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }

                    sectioned("Server") { serverCard }

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

                    sectioned("Notifications") {
                        notificationsCard
                        Text("Show a running timer on the Lock Screen and Dynamic Island.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }

                    if icons.isSupported {
                        sectioned("Appearance") {
                            appearanceCard
                            Text("Pick the Home Screen icon. All six are free.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .padding(.top, 2)
                        }
                    }

                    sectioned("Quick Log") {
                        quickFeedCard
                        Text("Defaults for the one-tap Feeding tile in the Quick Log widget.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }

                    sectioned("Support") {
                        supportCard
                        Text("Questions, feedback, or a bug? We'd love to hear from you.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.top, 2)
                    }

                    #if DEBUG
                    sectioned("Developer") { developerCard }
                    #endif

                    signOutCard.padding(.top, 4)

                    acknowledgementsFooter
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(BBColor.surface)
            .navigationTitle("Settings")
            .confirmationDialog("Contact Support", isPresented: $showingContactOptions, titleVisibility: .visible) {
                Button("Include Device Details") { presentMail(includeDiagnostics: true) }
                Button("Don't Include") { presentMail(includeDiagnostics: false) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Attach your device model, iOS version, and app version to help us investigate? Nothing else is shared.")
            }
            .sheet(item: $mailPayload) { payload in
                MailComposeView(recipient: SupportContact.recipient,
                                subject: SupportContact.subject,
                                body: payload.body) { mailPayload = nil }
                    .ignoresSafeArea()
            }
            .alert("Set Up Mail", isPresented: $showingMailUnavailable) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("No email account is set up on this device. You can reach us at \(SupportContact.recipient).")
            }
            .sheet(isPresented: $showingSupporter) { SupporterSheet(source: .settings) }
            .sheet(isPresented: $showingAcknowledgements) { AcknowledgementsView() }
            .sheet(isPresented: $showingPending) { PendingChangesView() }
            .sheet(item: $debugConflict) { c in
                NavigationStack { ConflictResolutionView(conflict: c) }
            }
            #if DEBUG
            // Second route to the picker, for `BB_APP_ICON=1` — the real one is the Appearance row.
            .navigationDestination(isPresented: $showingAppIcons) { AppIconPickerView() }
            #endif
            .sheet(isPresented: $debugIcons) {
                #if DEBUG
                NavigationStack { IconGalleryView() }
                #endif
            }
            .onAppear {
                hasSeenNudge = SupportNudgeStore.shared.hasShownANudge
                #if DEBUG
                if ProcessInfo.processInfo.environment["BB_OPEN_CONFLICT"] == "1" {
                    debugConflict = conflicts.first
                }
                if ProcessInfo.processInfo.environment["BB_ICONS"] == "1" {
                    debugIcons = true
                }
                if ProcessInfo.processInfo.environment["BB_SUPPORTER_SHEET"] == "1" {
                    showingSupporter = true
                }
                if ProcessInfo.processInfo.environment["BB_APP_ICON"] == "1" {
                    showingAppIcons = true
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
                .accessibilityLabel("Child photo")
                .accessibilityHint("Change photo")
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

    /// The server connection plus the offline-first sync truth (last sync, queued writes, conflicts)
    /// — combined into one "Server" card.
    private var serverCard: some View {
        card {
            if case .authenticated(let config) = session.state {
                serverRow(config)
                rowDivider
            }

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

    private func serverRow(_ config: ServerConfig) -> some View {
        SettingsRow(symbol: "cloud", tint: BBColor.brand,
                    glyphColor: BBColor.brandAccent, title: "Server") {
            HStack(spacing: 6) {
                Circle().fill(BBColor.success).frame(width: 7, height: 7)
                Text(config.baseURL.host() ?? config.baseURL.absoluteString)
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
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
                    set: { newValue in
                        lock.isEnabled = newValue
                        Analytics.settingChanged("appLock", enabled: newValue)
                    }))
                    .labelsHidden()
                    .tint(BBColor.primary)
                    .disabled(!lock.biometryAvailable)
            }
        }
    }

    // MARK: Notifications

    /// A running timer shown as a Live Activity / Dynamic Island. Toggling it reconciles
    /// immediately, so turning it off ends any live banner and turning it on starts one for a
    /// currently-running timer.
    private var notificationsCard: some View {
        card {
            SettingsRow(symbol: "clock.badge", tint: BBColor.info, title: "Live Activity") {
                Toggle("", isOn: Binding(
                    get: { liveActivitiesEnabled },
                    set: { newValue in
                        liveActivitiesEnabled = newValue
                        Analytics.settingChanged("liveActivities", enabled: newValue)
                        Task { await liveActivity.reconcile() }
                    }))
                    .labelsHidden()
                    .tint(BBColor.primary)
            }
        }
    }

    // MARK: Appearance

    /// The Home Screen icon, shown by name with the picker one tap away. Free for everyone — the
    /// row carries no lock, badge, or price, and never consults ``PurchaseManager``.
    private var appearanceCard: some View {
        card {
            NavigationLink {
                AppIconPickerView()
            } label: {
                SettingsRow(symbol: "paintbrush.fill", tint: BBColor.tummy, title: "App Icon") {
                    HStack(spacing: 4) {
                        Text(icons.selected.displayName)
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                        disclosure
                    }
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Quick Log

    /// The type + method the Quick Log widget's one-tap Feeding tile records. Stored in the App
    /// Group so the widget's App Intent reads the same values across the process boundary; changing
    /// them here changes what a future tap logs. Any FeedingType/Method combination is valid to the
    /// Baby Buddy API, so all choices are offered.
    private var quickFeedCard: some View {
        card {
            SettingsRow(symbol: "drop.fill", tint: BBColor.feeding, title: "Feeding type") {
                Menu {
                    Picker("Feeding type", selection: $quickFeedType) {
                        ForEach(FeedingType.allCases) { Text($0.label).tag($0) }
                    }
                } label: { menuValue(quickFeedType.label) }
            }
            rowDivider
            SettingsRow(symbol: "fork.knife", tint: BBColor.feeding, title: "Feeding method") {
                Menu {
                    Picker("Feeding method", selection: $quickFeedMethod) {
                        ForEach(FeedingMethod.allCases) { Text($0.label).tag($0) }
                    }
                } label: { menuValue(quickFeedMethod.label) }
            }
        }
    }

    /// Trailing label for a menu-backed settings row: the current value plus an up/down chevron,
    /// styled like the masthead's "Switch" affordance.
    private func menuValue(_ text: String) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BBColor.brandAccent)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Support the app

    /// A single row carrying supporter status, opening the ``SupporterSheet``. Nothing in the app
    /// is gated on supporting it, so the row is an invitation ("Join") rather than an upsell — and
    /// once someone has tipped it settles into a quiet green "Active".
    private var supporterCard: some View {
        card {
            Button {
                // No separate CTA signal: opening the sheet emits `Supporter.sheetViewed` with
                // `source: .settings` on this same tap, which is the same event counted once.
                showingSupporter = true
            } label: {
                SettingsRow(symbol: "heart.fill", tint: BBColor.brand,
                            glyphColor: BBColor.brandAccent, title: "Baby Buddy App Supporter") {
                    supporterStatus
                }
            }
            .buttonStyle(.plain)

            supportRemindersRow
        }
    }

    /// The opt-out for the support nudges (see ``SupportNudgeManager``), on by default.
    ///
    /// Held back until the first nudge has actually been shown. A switch offered before then asks
    /// someone to decide about something they have never seen — and pre-emptively turning it off
    /// would silence an ask they'd never have minded. Once they have met one, the control is theirs.
    /// It also disappears for supporters, who are never nudged at all, rather than sitting there
    /// governing nothing.
    @ViewBuilder private var supportRemindersRow: some View {
        if !purchases.isSupporter, hasSeenNudge {
            rowDivider
            SettingsRow(symbol: "sparkles", tint: BBColor.pumping, title: "Support reminders") {
                Toggle("", isOn: Binding(
                    get: { supportRemindersEnabled },
                    set: { newValue in
                        supportRemindersEnabled = newValue
                        Analytics.settingChanged("supportReminders", enabled: newValue)
                    }))
                    .labelsHidden()
                    .tint(BBColor.primary)
            }
        }
    }

    @ViewBuilder private var supporterStatus: some View {
        if purchases.isSupporter {
            HStack(spacing: 4) {
                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold))
                Text("Active")
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(BBColor.success)
        } else {
            HStack(spacing: 4) {
                Text("Join").font(.subheadline.weight(.medium)).foregroundStyle(BBColor.brandAccent)
                disclosure
            }
        }
    }

    private var disclosure: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.tertiary)
    }

    #if DEBUG
    /// Debug-only controls for the supporter/nudge states, which are otherwise slow or impossible to
    /// reach by hand. Compiled out of release (TestFlight/App Store) builds.
    ///
    /// "Supporter mode" overrides status in both directions — forcing it *off* is the only way to see
    /// the ask, and the nudges, on a device that has genuinely tipped. "Arm support nudge" ages the
    /// counters past every gate so the real policy fires on the next Dashboard visit, and "Reset"
    /// puts them back to a fresh install.
    private var developerCard: some View {
        card {
            SettingsRow(symbol: "wand.and.stars", tint: BBColor.warning, title: "Supporter mode") {
                Menu {
                    Picker("Supporter mode", selection: Binding(
                        get: { purchases.debugSupporterOverride },
                        set: { purchases.setDebugSupporter($0) })) {
                        ForEach(PurchaseManager.DebugSupporterOverride.allCases) {
                            Text($0.label).tag($0)
                        }
                    }
                } label: { menuValue(purchases.debugSupporterOverride.label) }
            }

            rowDivider

            Button { SupportNudgeStore.shared.debugArm() } label: {
                SettingsRow(symbol: "bell.badge", tint: BBColor.pumping, title: "Arm support nudge") {
                    Text("Go to Home").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            rowDivider

            Button { SupportNudgeStore.shared.debugReset() } label: {
                SettingsRow(symbol: "arrow.counterclockwise", tint: BBColor.restart,
                            title: "Reset support nudges") {
                    Text("Fresh install").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }
    #endif

    // MARK: Support

    /// A single "Contact Support" row that opens an email to the Baby Buddy team. Tapping first
    /// offers to attach diagnostics, then presents the in-app mail composer.
    private var supportCard: some View {
        card {
            Button { showingContactOptions = true } label: {
                SettingsRow(symbol: "envelope", tint: BBColor.info, title: "Contact Support") {
                    disclosure
                }
            }
            .buttonStyle(.plain)

            rowDivider

            Link(destination: Self.reviewURL) {
                SettingsRow(symbol: "star", tint: BBColor.warning, title: "Rate on the App Store") {
                    disclosure
                }
            }
            .buttonStyle(.plain)
        }
    }

    /// Opens the App Store listing with its review composer already up. Deliberately not
    /// `SKStoreReviewController`: the system prompt is rate-limited and silently does nothing once
    /// a user has seen it, which is wrong for a row they tapped on purpose.
    private static let reviewURL =
        URL(string: "https://apps.apple.com/app/id6788966667?action=write-review")!

    /// Present the mail composer seeded with (optionally) diagnostics. Falls back to a `mailto:`
    /// link, then a "set up Mail" alert, when the in-app composer can't be shown.
    private func presentMail(includeDiagnostics: Bool) {
        if SupportContact.canSendMail {
            mailPayload = MailPayload(body: SupportContact.body(includeDiagnostics: includeDiagnostics))
        } else if let url = SupportContact.mailtoURL(includeDiagnostics: includeDiagnostics) {
            openURL(url) { accepted in
                if !accepted { showingMailUnavailable = true }
            }
        } else {
            showingMailUnavailable = true
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

    // MARK: Acknowledgements

    /// A deliberately quiet footer link — third-party license disclosures and the Baby Buddy
    /// open-source credit live one tap away, without competing with the settings above.
    private var acknowledgementsFooter: some View {
        Button { showingAcknowledgements = true } label: {
            Text("Acknowledgements")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 10)
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
struct SettingsRow<Trailing: View>: View {
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

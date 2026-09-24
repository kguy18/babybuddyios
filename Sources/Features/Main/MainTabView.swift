import SwiftUI
import SwiftData

/// Root tab bar shown once authenticated. Owns the selected-child state shared by the
/// Dashboard and Timeline tabs, and kicks off an initial pull.
struct MainTabView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(DeepLinkRouter.self) private var router
    @Environment(AppSession.self) private var session
    @Environment(AppLockManager.self) private var lock
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<LocalEntity> { $0.kindRaw == "timer" })
    private var timers: [LocalEntity]
    @Query(filter: #Predicate<LocalEntity> { $0.kindRaw == "child" }, sort: \.timestamp)
    private var children: [LocalEntity]
    /// Every cached dose, for every child: medicine colors follow the order names first appear.
    @Query(filter: #Predicate<LocalEntity> { $0.kindRaw == "medication" })
    private var medications: [LocalEntity]
    @State private var sickMode = SickModeStore.shared
    // Stored in the App Group suite so the timer widget/intents target the same child.
    @AppStorage("selectedChildID", store: SharedDefaults.suite) private var selectedChildID = 0
    /// The marketing version whose What's New card has been seen on this device. App-local, not in
    /// the App Group suite: the widget has no use for it.
    @AppStorage(ReleaseNotes.lastSeenKey) private var lastWhatsNewVersion = ""
    @State private var selectedTab = initialTab
    @State private var whatsNew: ReleaseNote?

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedChildID: childBinding)
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
                // Sick mode's red dot: a native badge with no text draws as a dot. Not an overlay,
                // since one on the TabView doesn't take taps on iOS 26.
                .badge(sickMode[selectedChildID].startedAt == nil ? nil : Text(""))
            TimelineView(selectedChildID: childBinding)
                .tabItem { Label("Timeline", systemImage: "list.bullet") }.tag(1)
            InsightsView(selectedChildID: childBinding)
                .tabItem { Label("Trends", systemImage: "chart.bar.fill") }.tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(3)
        }
        .task {
            await sync.sync()
            ensureValidSelection()
        }
        .task(id: shouldPollTimers) {
            guard shouldPollTimers else { return }
            var delay: Duration = .seconds(5)
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: delay)
                    guard shouldPollTimers else { return }
                    let changed = try await sync.remoteTimersChanged()
                    try Task.checkCancellation()
                    guard shouldPollTimers else { return }
                    if changed {
                        // Deleting the last timer cancels this polling task. Let the already
                        // started full sync finish saving and reconciling its timer surfaces.
                        await Task { await sync.sync() }.value
                    }
                    delay = .seconds(5)
                } catch {
                    if Task.isCancelled { return }
                    delay = .seconds(30)
                }
            }
        }
        .onChange(of: children.map(\.serverID)) { _, _ in ensureValidSelection() }
        .onChange(of: router.openTimerLocalID) { _, id in
            if id != nil { selectedTab = 0 } // a timer deep link targets the Home tab
        }
        .onChange(of: router.convertTarget) { _, target in
            if target != nil { selectedTab = 0 }
        }
        .onChange(of: router.repeatDoseLocalID) { _, id in
            if id != nil { selectedTab = 0 } // a medication reminder targets the Home tab
        }
        .onChange(of: router.openDayKind) { _, kind in
            if kind != nil { selectedTab = 0 } // a status-widget tile targets the Home tab
        }
        .onChange(of: router.showTimelineKind) { _, kind in
            if kind != nil { selectedTab = 1 } // a Latest row targets the Timeline tab
        }
        .onChange(of: router.showTimeline) { _, show in
            if show { selectedTab = 1; router.showTimeline = false } // sick mode's "See all"
        }
        .onChange(of: medications.map(\.payload), initial: true) { _, _ in
            MedicineColorStore.shared.assign(medications)
        }
        .sheet(isPresented: Binding(get: { router.showSupporter },
                                    set: { router.showSupporter = $0 })) {
            SupporterSheet(source: .deeplink)
        }
        .onAppear { presentWhatsNewIfNeeded() }
        // A cover presents above the lock screen, so a locked launch waits for the unlock.
        .onChange(of: lock.isLocked) { _, locked in
            if !locked {
                presentWhatsNewIfNeeded()
                if scenePhase == .active { Task { await sync.sync() } }
            }
        }
        .fullScreenCover(item: $whatsNew) { note in
            WhatsNewView(note: note, source: .launch) {
                lastWhatsNewVersion = ReleaseNotes.currentVersion
            }
        }
        .safeAreaInset(edge: .top) {
            if !sync.isOnline {
                Label("Offline — changes will sync when reconnected", systemImage: "wifi.slash")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.orange.opacity(0.2))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        // Announce the connectivity change so it isn't a silent, purely-visual banner.
        .onChange(of: sync.isOnline) { _, online in
            AccessibilityNotification.Announcement(
                online ? "Back online" : "Offline. Changes will sync when reconnected.").post()
        }
    }

    private var shouldPollTimers: Bool {
        #if DEBUG
        if session.isDemo { return false }
        #endif
        return scenePhase == .active && session.isAuthenticated && !lock.isLocked && sync.isOnline
            && timers.contains { $0.serverID != nil && $0.syncState != .pendingDelete }
    }

    /// Show the What's New card once per marketing version, and only to someone who was already
    /// running an earlier one — a fresh install has onboarding to introduce the app, so signing in
    /// records the version (`ReleaseNotes.markCurrentSeen`) and cards start from the next update.
    /// Nothing recorded at all therefore means an update from a release older than the card
    /// itself (1.0.x), which is shown it: 1.1.0 build 1 treated that as a fresh install, and the
    /// first card never reached anyone. The version is written when the card is dismissed, not
    /// here, so a crash on the way up doesn't swallow the release.
    private func presentWhatsNewIfNeeded() {
        guard !lock.isLocked else { return }
        let current = ReleaseNotes.currentVersion
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["BB_OPEN_WHATSNEW"] == "1" {
            whatsNew = ReleaseNotes.note(for: current) ?? ReleaseNotes.all().first
            return
        }
        // Demo mode never signs in, so nothing stamps the version and every demo launch would
        // look like that update. `BB_WHATSNEW_UPGRADE=1` asks for exactly that.
        if session.isDemo, lastWhatsNewVersion.isEmpty, environment["BB_WHATSNEW_UPGRADE"] != "1" {
            lastWhatsNewVersion = current
            return
        }
        #endif
        guard !current.isEmpty, lastWhatsNewVersion != current else { return }
        // A release that shipped without a `whatsnew` block simply has nothing to say. Record it
        // rather than re-reading the file on every launch until the next release.
        guard let note = ReleaseNotes.note(for: current) else {
            lastWhatsNewVersion = current
            return
        }
        whatsNew = note
    }

    private static var initialTab: Int {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["BB_START_TAB"] {
        case "timeline": return 1
        case "trends": return 2
        case "settings": return 3
        default: return 0
        }
        #else
        return 0
        #endif
    }

    private var childBinding: Binding<Int> {
        Binding(get: { selectedChildID }, set: { selectedChildID = $0 })
    }

    /// Default to the first child if none is selected or the selection no longer exists.
    private func ensureValidSelection() {
        let ids = children.compactMap(\.serverID)
        if !ids.contains(selectedChildID), let first = ids.first {
            selectedChildID = first
        }
    }
}

/// Toolbar control for switching between children (hidden when there's only one).
struct ChildSwitcher: ToolbarContent {
    let children: [LocalEntity]
    @Binding var selectedChildID: Int

    var body: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            if children.count > 1 {
                Menu {
                    ForEach(children, id: \.serverID) { child in
                        Button {
                            if let id = child.serverID { selectedChildID = id }
                        } label: {
                            Label(childName(child), systemImage: child.serverID == selectedChildID
                                  ? "checkmark" : "person.crop.circle")
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        avatar
                        Text(currentName).font(.headline)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Current child, \(currentName)")
                    .accessibilityHint("Switch child")
                }
            } else {
                HStack(spacing: 6) {
                    avatar
                    Text(currentName).font(.headline)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Current child, \(currentName)")
            }
        }
    }

    private var avatar: some View {
        ChildAvatar(
            pictureURL: selectedChild?.payloadObject["picture"] as? String,
            initial: String(currentName.prefix(1)),
            size: 26)
    }

    private var selectedChild: LocalEntity? {
        children.first { $0.serverID == selectedChildID }
    }

    private var currentName: String {
        selectedChild.map(childName) ?? "Baby Buddy"
    }

    private func childName(_ entity: LocalEntity) -> String {
        let p = entity.payloadObject
        let first = p["first_name"] as? String ?? ""
        let last = p["last_name"] as? String ?? ""
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? "Child" : name
    }
}

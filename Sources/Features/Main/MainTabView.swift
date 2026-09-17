import SwiftUI
import SwiftData

/// Root tab bar shown once authenticated. Owns the selected-child state shared by the
/// Dashboard and Timeline tabs, and kicks off an initial pull.
struct MainTabView: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(DeepLinkRouter.self) private var router
    @Query(filter: #Predicate<LocalEntity> { $0.kindRaw == "child" }, sort: \.timestamp)
    private var children: [LocalEntity]
    // Stored in the App Group suite so the timer widget/intents target the same child.
    @AppStorage("selectedChildID", store: SharedDefaults.suite) private var selectedChildID = 0
    @State private var selectedTab = initialTab
    /// The release notes waiting to be shown, if any. Resolved once, in `.task`.
    @State private var whatsNew: WhatsNewRelease?
    /// Which button closed the What's New sheet. `nil` at dismissal means it was swiped away —
    /// SwiftUI's `onDismiss` fires the same for a swipe and a programmatic close, so the button
    /// taps have to record themselves. Same shape as the Dashboard's `acceptedNudge`.
    @State private var whatsNewAction: Analytics.WhatsNewAction?
    /// Presentation state for the supporter sheet, whichever door opened it.
    @State private var showingSupporter = false
    /// The door itself — the tip's attribution. See ``Analytics/SupporterSource``.
    @State private var supporterSource: Analytics.SupporterSource = .deeplink

    var body: some View {
        TabView(selection: $selectedTab) {
            DashboardView(selectedChildID: childBinding)
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            TimelineView(selectedChildID: childBinding)
                .tabItem { Label("Timeline", systemImage: "list.bullet") }.tag(1)
            InsightsView(selectedChildID: childBinding)
                .tabItem { Label("Trends", systemImage: "chart.bar.fill") }.tag(2)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape.fill") }.tag(3)
        }
        .task {
            // Before the first sync: the sheet is about this build, not about the server's data,
            // and resolving it here means a slow first pull can't delay or suppress it.
            whatsNew = WhatsNewStore.pending(release: WhatsNewRelease.bundled,
                                             currentVersion: WhatsNewStore.currentVersion)
            if let whatsNew {
                lastShownWhatsNewVersion = whatsNew.version
                WhatsNewStore.shownThisLaunch = true
                Analytics.whatsNewShown(version: whatsNew.version, entries: whatsNew.entries.count)
            }
            await sync.sync()
            ensureValidSelection()
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
        // Shown once per version, over whichever tab is open. `onDismiss` is where the outcome is
        // reported, so a swipe-away is counted as deliberately as a tap.
        .sheet(item: $whatsNew, onDismiss: finishWhatsNew) { release in
            WhatsNewSheet(release: release) { whatsNewAction = $0 }
        }
        // One presenter for the supporter sheet; `supporterSource` is what distinguishes the deep
        // link from the What's New button, so a tip is attributable to the door it came through.
        .sheet(isPresented: $showingSupporter, onDismiss: { router.showSupporter = false }) {
            SupporterSheet(source: supporterSource)
        }
        .onChange(of: router.showSupporter) { _, show in
            guard show else { return }
            supporterSource = .deeplink
            showingSupporter = true
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

    /// The What's New sheet closed. Reports how — a dismissal with no recorded button tap is a
    /// swipe — and, for the support button, opens the supporter sheet in its place.
    ///
    /// The supporter sheet is presented *here*, after this one has gone, rather than stacked on top
    /// of it: the same handoff the Dashboard makes from a milestone nudge.
    private func finishWhatsNew() {
        guard let version = lastShownWhatsNewVersion else { return }
        let action = whatsNewAction ?? .swiped
        whatsNewAction = nil
        Analytics.whatsNewDismissed(version: version, action: action)
        guard action == .support else { return }
        supporterSource = .whatsNew
        showingSupporter = true
    }

    /// The version the sheet just closed on. `.sheet(item:)` clears its binding before `onDismiss`
    /// runs, so the release itself is gone by then — only the version is needed, so it is kept
    /// rather than holding the whole value alive.
    @State private var lastShownWhatsNewVersion: String?

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

import SwiftUI
import SwiftData
import BackgroundTasks
import WidgetKit

@main
struct BabyBuddyApp: App {
    @State private var session: AppSession
    @State private var sync: SyncEngine
    @State private var purchases: PurchaseManager
    @State private var lock = AppLockManager()
    @State private var router = DeepLinkRouter()
    @State private var liveActivity = LiveActivityManager()
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    private static let refreshTaskID = "com.kurtisguy.BabyBuddy.sync"

    /// Whether this process is running the unit-test suite rather than serving a customer.
    ///
    /// `BabyBuddyTests` is hosted *in* the app (`TEST_HOST`), so this initializer runs before the
    /// tests do. Left unguarded, a plain `xcodebuild test` stamps a first launch and counts every
    /// record the persistence tests create into the real support-nudge counters — leaving any
    /// simulator that has run the suite with a pre-aged, pre-counted install that can't be used to
    /// check the day-7 / 10-entry gate by hand. ``PurchaseManagerTests`` guards its own defaults the
    /// same way, by save-and-restore; automatic wiring has no test to do that from.
    ///
    /// XCTest is never loaded into a release build, so this is always `false` in the shipped app.
    private static var isHostingTests: Bool {
        NSClassFromString("XCTestCase") != nil
    }

    init() {
        Analytics.start()
        if !Self.isHostingTests {
            // Stamped before any Dashboard can ask whether a support nudge is due — every time-based
            // rule in the policy hangs off it.
            SupportNudgeStore.shared.registerFirstLaunch()
            // Count records logged in the app, which is the nudge policy's usage gate. See the hook's
            // documentation for why `LocalRepository` doesn't reach for the store directly.
            LocalRepository.didLogActivity = { SupportNudgeStore.shared.recordLoggedEntry() }
        }
        let container = LocalStore.makeContainer()
        let session = AppSession()
        let purchases = PurchaseManager()
        purchases.start()
        self.container = container
        _session = State(initialValue: session)
        _sync = State(initialValue: SyncEngine(session: session, context: container.mainContext))
        _purchases = State(initialValue: purchases)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(sync)
                .environment(purchases)
                .environment(lock)
                .environment(router)
                .environment(liveActivity)
                .modelContainer(container)
                .onOpenURL { router.handle($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                lock.willEnterForeground()
                if session.isAuthenticated && !lock.isLocked { Task { await sync.sync() } }
                // Sync the Live Activity to the current running timer — covers timers started or
                // stopped from the widget/Siri, whose extension-process intents can't touch it.
                Task { await liveActivity.reconcile() }
            case .background:
                lock.didEnterBackground()
                scheduleBackgroundSync()
                WidgetCenter.shared.reloadAllTimelines() // reflect in-app timer changes on the widgets
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(Self.refreshTaskID)) {
            await sync.sync()
            await MainActor.run { scheduleBackgroundSync() }
        }
    }

    private func scheduleBackgroundSync() {
        let request = BGAppRefreshTaskRequest(identifier: Self.refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}

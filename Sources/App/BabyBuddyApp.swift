import SwiftUI
import SwiftData
import BackgroundTasks
import WidgetKit

@main
struct BabyBuddyApp: App {
    @State private var session: AppSession
    @State private var sync: SyncEngine
    @State private var subscriptions: Subscriptions
    @State private var lock = AppLockManager()
    @State private var router = DeepLinkRouter()
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    private static let refreshTaskID = "com.kurtisguy.BabyBuddy.sync"

    init() {
        Analytics.start()
        let container = LocalStore.makeContainer()
        let session = AppSession()
        let subscriptions = Subscriptions()
        subscriptions.start()
        self.container = container
        _session = State(initialValue: session)
        _sync = State(initialValue: SyncEngine(session: session, context: container.mainContext))
        _subscriptions = State(initialValue: subscriptions)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(sync)
                .environment(subscriptions)
                .environment(lock)
                .environment(router)
                .modelContainer(container)
                .onOpenURL { router.handle($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                lock.willEnterForeground()
                if session.isAuthenticated && !lock.isLocked { Task { await sync.sync() } }
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

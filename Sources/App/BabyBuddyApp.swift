import SwiftUI
import SwiftData
import BackgroundTasks

@main
struct BabyBuddyApp: App {
    @State private var session: AppSession
    @State private var sync: SyncEngine
    @State private var lock = AppLockManager()
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    private static let refreshTaskID = "com.kurtisguy.BabyBuddy.sync"

    init() {
        let container = LocalStore.makeContainer()
        let session = AppSession()
        self.container = container
        _session = State(initialValue: session)
        _sync = State(initialValue: SyncEngine(session: session, context: container.mainContext))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(sync)
                .environment(lock)
                .modelContainer(container)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                lock.willEnterForeground()
                if session.isAuthenticated && !lock.isLocked { Task { await sync.sync() } }
            case .background:
                lock.didEnterBackground()
                scheduleBackgroundSync()
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

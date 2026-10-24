import Foundation

/// Small values shared between the app and its widget/intents extension via the App Group's
/// `UserDefaults` suite. The app writes; the extension reads. Keep this limited to a few
/// primitives — the SwiftData store (see ``LocalStore``) is the source of truth for records.
enum SharedDefaults {
    static let suite = UserDefaults(suiteName: LocalStore.appGroupID) ?? .standard

    private static let selectedChildKey = "selectedChildID"
    private static let liveActivitiesEnabledKey = "liveActivitiesEnabled"
    private static let isSupporterKey = "isSupporter"
    private static let quickFeedTypeKey = "quickFeedType"
    private static let quickFeedMethodKey = "quickFeedMethod"
    private static let lastSyncDateKey = "lastSyncDate"
    static let stalenessThresholdKey = "stalenessThresholdMinutes"

    /// Whether the customer has tipped at least once. Written by the app (from ``PurchaseManager``)
    /// and readable by the widgets / App Intents across the process boundary. Nothing is gated on
    /// it — every feature is free; it's bridged here for supporter-only cosmetics later. Defaults to
    /// `false` until the app writes it.
    static var isSupporter: Bool {
        get { suite.object(forKey: isSupporterKey) as? Bool ?? false }
        set { suite.set(newValue, forKey: isSupporterKey) }
    }

    /// The child the dashboard is currently focused on, so widget-started timers attach to the
    /// same child. `nil` means "unassigned" (Baby Buddy timers allow a null child).
    static var selectedChildID: Int? {
        get { suite.object(forKey: selectedChildKey) as? Int }
        set {
            if let newValue { suite.set(newValue, forKey: selectedChildKey) }
            else { suite.removeObject(forKey: selectedChildKey) }
        }
    }

    /// The feeding type/method the Quick Log widget's one-tap "Feeding" tile logs. Edited in the
    /// app's Settings and read here by the widget's App Intent across the process boundary, so a
    /// tap always records the customer's current default. Default to breast milk / both breasts.
    /// Keys/defaults are mirrored by the `@AppStorage` bindings in Settings — keep them in sync.
    static var quickFeedType: FeedingType {
        get { suite.string(forKey: quickFeedTypeKey).flatMap(FeedingType.init(rawValue:)) ?? .breastMilk }
        set { suite.set(newValue.rawValue, forKey: quickFeedTypeKey) }
    }

    static var quickFeedMethod: FeedingMethod {
        get { suite.string(forKey: quickFeedMethodKey).flatMap(FeedingMethod.init(rawValue:)) ?? .bothBreasts }
        set { suite.set(newValue.rawValue, forKey: quickFeedMethodKey) }
    }

    /// Whether a running timer is shown as a Live Activity / Dynamic Island. Defaults to on;
    /// read by ``LiveActivityManager`` when it reconciles. Keep the key in sync with the
    /// `@AppStorage` binding in Settings.
    static var liveActivitiesEnabled: Bool {
        get { suite.object(forKey: liveActivitiesEnabledKey) as? Bool ?? true }
        set { suite.set(newValue, forKey: liveActivitiesEnabledKey) }
    }

    /// When the app last pulled successfully — written by ``SyncEngine``, read by the status
    /// widget for its freshness stamp. `nil` until the first sync.
    static var lastSyncDate: Date? {
        get { suite.object(forKey: lastSyncDateKey) as? Date }
        set { suite.set(newValue, forKey: lastSyncDateKey) }
    }

    /// Minutes since the last sync after which the freshness stamp turns to the warning colour;
    /// `0` is Off. Mirrored by the `@AppStorage` binding in Settings — keep the key in sync.
    static var stalenessThresholdMinutes: Int {
        suite.object(forKey: stalenessThresholdKey) as? Int ?? SyncFreshness.defaultThresholdMinutes
    }

    /// A timer ``OpenTimerIntent`` asked the app to show. Written by the intent, which may run in
    /// the widget's process, and taken (read and cleared) by the app when it becomes active.
    static var pendingOpenTimerID: UUID? {
        get { suite.string(forKey: pendingOpenTimerKey).flatMap(UUID.init(uuidString:)) }
        set { suite.set(newValue?.uuidString, forKey: pendingOpenTimerKey) }
    }
    private static let pendingOpenTimerKey = "pendingOpenTimerID"
}

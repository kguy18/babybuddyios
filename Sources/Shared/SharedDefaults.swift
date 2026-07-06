import Foundation

/// Small values shared between the app and its widget/intents extension via the App Group's
/// `UserDefaults` suite. The app writes; the extension reads. Keep this limited to a few
/// primitives — the SwiftData store (see ``LocalStore``) is the source of truth for records.
enum SharedDefaults {
    static let suite = UserDefaults(suiteName: LocalStore.appGroupID) ?? .standard

    private static let selectedChildKey = "selectedChildID"
    private static let liveActivitiesEnabledKey = "liveActivitiesEnabled"
    private static let isPremiumKey = "isPremium"

    /// Whether the customer has premium access. Written by the app (from ``PurchaseManager``) and
    /// read by the widgets / App Intents to gate the premium "Home Screen Widgets" feature across
    /// the process boundary. Defaults to `false` (locked) until the app writes it.
    static var isPremium: Bool {
        get { suite.object(forKey: isPremiumKey) as? Bool ?? false }
        set { suite.set(newValue, forKey: isPremiumKey) }
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

    /// Whether a running timer is shown as a Live Activity / Dynamic Island. Defaults to on;
    /// read by ``LiveActivityManager`` when it reconciles. Keep the key in sync with the
    /// `@AppStorage` binding in Settings.
    static var liveActivitiesEnabled: Bool {
        get { suite.object(forKey: liveActivitiesEnabledKey) as? Bool ?? true }
        set { suite.set(newValue, forKey: liveActivitiesEnabledKey) }
    }
}

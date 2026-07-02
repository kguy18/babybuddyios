import Foundation
import Observation

/// Manages an optional **local** 14-day free trial of premium features.
///
/// The trial is entirely local: it uses `UserDefaults` for persistence and never touches RevenueCat
/// or StoreKit. While the trial is active, callers should treat the customer as having full premium
/// access (see ``FeatureAccess`` — pass ``isTrialActive`` as `isTrial`).
///
/// **The trial never starts on its own.** Displaying a trial-offer modal must not call
/// ``startTrial()`` — only an explicit user action (e.g. a "Start Free Trial" button) should. Once
/// started, the trial runs for exactly 14 days and **cannot be restarted** after it expires:
/// ``startTrial()`` is a permanent one-shot guarded by the persisted ``hasStartedTrial`` flag.
@MainActor
@Observable
final class TrialManager {
    /// Trial length, measured from the instant ``startTrial()`` is called.
    static let trialDuration: TimeInterval = 14 * 24 * 60 * 60 // 14 days

    private enum Key {
        static let startDate = "purchases.trialStartDate"
        static let hasStarted = "purchases.hasStartedTrial"
        static let endReported = "purchases.trialEndReported"
    }

    private let defaults: UserDefaults
    /// Injectable clock so the time-based properties can be tested deterministically.
    private let now: () -> Date

    /// Whether the trial has ever been started. Once `true` it stays `true` for good — this is what
    /// prevents a second trial after the first one expires. Persisted independently of the date.
    private(set) var hasStartedTrial: Bool

    /// The moment the trial began, or `nil` if it was never started. Persisted.
    private(set) var trialStartDate: Date?

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
        self.hasStartedTrial = defaults.bool(forKey: Key.hasStarted)
        self.trialStartDate = defaults.object(forKey: Key.startDate) as? Date
    }

    // MARK: - Derived state

    /// The instant the trial ends, or `nil` if it was never started.
    private var trialEndDate: Date? {
        trialStartDate?.addingTimeInterval(Self.trialDuration)
    }

    /// `true` while a started trial is still within its 14-day window.
    var isTrialActive: Bool {
        guard let end = trialEndDate else { return false }
        return now() < end
    }

    /// `true` once a started trial has passed its 14-day window. `false` if a trial was never started.
    var isTrialExpired: Bool {
        guard let end = trialEndDate else { return false }
        return now() >= end
    }

    /// Whole days left in an active trial (rounded up so any remaining time counts as a full day).
    /// `0` when the trial has expired or was never started.
    var daysRemaining: Int {
        guard let end = trialEndDate else { return 0 }
        let secondsLeft = end.timeIntervalSince(now())
        guard secondsLeft > 0 else { return 0 }
        return Int(ceil(secondsLeft / 86_400))
    }

    // MARK: - Actions

    /// Starts the free trial **now**. Must be called only in response to an explicit user action.
    ///
    /// This is a permanent one-shot: if the trial has already been started (whether currently active
    /// or long expired) this is a no-op, so an expired trial can never be restarted.
    func startTrial() {
        guard !hasStartedTrial else { return }
        let start = now()
        trialStartDate = start
        hasStartedTrial = true
        defaults.set(start, forKey: Key.startDate)
        defaults.set(true, forKey: Key.hasStarted)
        Analytics.trialStarted()
    }

    /// Emit `Trial.ended` once, the first time an elapsed trial is observed. Call at launch and when
    /// the app becomes active — the persisted flag guarantees it fires at most once per trial.
    /// (A trial expires by the passage of time, so there's no natural event; this reconciles it.)
    func reportTrialEndIfNeeded() {
        guard hasStartedTrial, isTrialExpired,
              !defaults.bool(forKey: Key.endReported) else { return }
        defaults.set(true, forKey: Key.endReported)
        Analytics.trialEnded()
    }

    /// Clears all trial state. Intended for tests and debug tooling only — production code must never
    /// call this, as it would defeat the no-restart guarantee.
    func reset() {
        trialStartDate = nil
        hasStartedTrial = false
        defaults.removeObject(forKey: Key.startDate)
        defaults.removeObject(forKey: Key.hasStarted)
        defaults.removeObject(forKey: Key.endReported)
    }
}

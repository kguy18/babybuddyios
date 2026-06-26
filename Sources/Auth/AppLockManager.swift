import Foundation
import LocalAuthentication
import Observation

/// Optional Face ID / Touch ID gate. When enabled, the app locks on launch and after
/// being backgrounded beyond a short grace period, requiring biometric (or device
/// passcode) authentication to reveal content.
@MainActor
@Observable
final class AppLockManager {
    private let enabledKey = "appLockEnabled"
    private let graceSeconds: TimeInterval = 30

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            if !isEnabled { isLocked = false }
        }
    }

    /// True when content should be hidden behind the lock screen.
    private(set) var isLocked: Bool
    private var backgroundedAt: Date?

    /// Whether the device can actually perform biometric/passcode auth.
    var biometryAvailable: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    init() {
        var enabled = UserDefaults.standard.bool(forKey: enabledKey)
        #if DEBUG
        if ProcessInfo.processInfo.environment["BB_LOCK"] == "1" { enabled = true }
        #endif
        isEnabled = enabled
        isLocked = enabled
    }

    func didEnterBackground() {
        guard isEnabled else { return }
        backgroundedAt = .now
    }

    func willEnterForeground() {
        guard isEnabled, let backgroundedAt else { return }
        if Date.now.timeIntervalSince(backgroundedAt) > graceSeconds {
            isLocked = true
        }
        self.backgroundedAt = nil
    }

    /// Prompt for biometrics. On success, unlock.
    func unlock() async {
        guard isEnabled else { isLocked = false; return }
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Passcode"
        // Evaluate availability first so `biometryType` is populated for analytics.
        _ = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
        let biometry = Self.biometryName(context.biometryType)
        do {
            let ok = try await context.evaluatePolicy(
                .deviceOwnerAuthentication, localizedReason: "Unlock Baby Buddy")
            isLocked = !ok
            Analytics.appLockUnlock(result: ok ? .success : .failure, biometry: biometry)
        } catch {
            isLocked = true
            Analytics.appLockUnlock(result: .failure, biometry: biometry)
        }
    }

    private static func biometryName(_ type: LABiometryType) -> String {
        switch type {
        case .faceID: return "faceID"
        case .touchID: return "touchID"
        case .opticID: return "opticID"
        case .none: return "none"
        @unknown default: return "unknown"
        }
    }
}

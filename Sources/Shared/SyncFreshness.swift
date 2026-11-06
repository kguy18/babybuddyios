import Foundation

/// Data-freshness stamp shared by the Dashboard header and the status widget: "Updated 4m ago",
/// turning to the warning colour once the last successful sync is older than the threshold.
/// Pure so the threshold logic is testable with an injected clock.
enum SyncFreshness {
    /// Threshold choices offered in Settings, in minutes; `0` means Off (never stale).
    static let thresholdOptions = [0, 15, 30, 60, 120]
    static let defaultThresholdMinutes = 30

    static func isStale(lastSync: Date?, now: Date, thresholdMinutes: Int) -> Bool {
        guard thresholdMinutes > 0 else { return false }
        guard let lastSync else { return true }
        return now.timeIntervalSince(lastSync) > TimeInterval(thresholdMinutes * 60)
    }

    /// "Updated 4m ago" / "Updated now" / "Not synced yet".
    static func label(lastSync: Date?, now: Date) -> String {
        guard let lastSync else { return String(localized: "Not synced yet") }
        let age = ChildStatus.compactAge(from: lastSync, to: now)
        return now.timeIntervalSince(lastSync) < 60 ? String(localized: "Updated just now") : String(localized: "Updated \(age) ago")
    }

    static func thresholdLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: return String(localized: "Off")
        case ..<60: return String(localized: "\(minutes) min")
        default: return minutes % 60 == 0 ? String(localized: "\(minutes / 60) h") : String(localized: "\(minutes / 60) h \(minutes % 60) min")
        }
    }
}

import Foundation
import SwiftData
import UserNotifications

/// Which running timers deserve a "still running" nudge, and when. Pure so it's testable; the
/// thresholds are per activity and live in the App Group defaults (Settings › Notifications).
enum ForgottenTimerPolicy {
    static let enabledKey = "forgottenTimerAlertsEnabled"
    static var isEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BB_TIMER_ALERT_SECONDS"] != nil { return true }
        #endif
        return SharedDefaults.suite.bool(forKey: enabledKey)
    }

    /// The threshold choices Settings offers for an activity, in seconds. Sleep runs to a day;
    /// a feeding, pumping or tummy-time timer past 4 hours has already filed a bogus record, so
    /// those stop there and start at 10 minutes instead.
    static func choices(for activity: TimerActivity?) -> [TimeInterval] {
        switch activity {
        case .sleep, nil: return [1800, 3600, 7200, 14_400, 28_800, 43_200, 86_400]
        case .feeding, .pumping, .tummyTime: return [600, 900, 1800, 2700, 3600, 7200, 14_400]
        }
    }

    static func thresholdKey(_ activity: TimerActivity) -> String { "forgottenTimerThreshold.\(activity.rawValue)" }

    static func defaultThreshold(_ activity: TimerActivity?) -> TimeInterval {
        switch activity {
        case .feeding, .pumping: return 7200
        case .sleep: return 43_200
        case .tummyTime: return 3600
        case nil: return 14_400 // ponytail: untyped timers aren't configurable; add a row if asked
        }
    }

    /// The configured threshold for an activity. `BB_TIMER_ALERT_SECONDS=<n>` (DEBUG) turns alerts
    /// on and overrides every threshold so the alert can be exercised without waiting hours.
    static func threshold(for activity: TimerActivity?) -> TimeInterval {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["BB_TIMER_ALERT_SECONDS"], let n = Double(s) {
            return n
        }
        #endif
        guard let activity else { return defaultThreshold(nil) }
        // A value Settings no longer offers (8/12/24 h left the non-sleep lists in 1.1.0) falls
        // back to the default rather than lingering where the picker can't show it.
        let stored = SharedDefaults.suite.double(forKey: thresholdKey(activity))
        return choices(for: activity).contains(stored) ? stored : defaultThreshold(activity)
    }

    struct Request: Equatable {
        let id: String
        let fireDate: Date
        let title: String
        let body: String
        let url: String
    }

    static func identifier(for timer: LocalEntity) -> String { "timer-\(timer.localID.uuidString)" }

    /// The notification a running timer should fire once it passes its threshold.
    static func request(for timer: LocalEntity, childName: String?,
                        threshold: TimeInterval? = nil) -> Request {
        let activity = TimerActivity(timer: timer)
        let limit = threshold ?? self.threshold(for: activity)
        let name = activity?.timerName ?? (timer.payloadObject["name"] as? String) ?? "Timer"
        let owner = childName.map { "\($0)'s " } ?? ""
        return Request(
            id: identifier(for: timer),
            fireDate: timer.timestamp.addingTimeInterval(limit),
            title: "\(name) timer still running",
            body: "\(owner)\(name.lowercased()) timer has been running for "
                + "\(EntityFormatting.formatInterval(limit)). Tap to stop it.",
            url: "babybuddy://timer/\(timer.localID.uuidString)")
    }

    /// Diff wanted requests against what the notification center already holds, for the requests
    /// whose identifiers start with `prefix`: schedule what's missing or moved, drop what is no
    /// longer wanted. A request that has already been delivered is left alone so it nags once, not
    /// on every foreground. With `firesOverdue` a request whose time has already passed is
    /// scheduled "now" and so can't be date-matched — it is kept as long as it is pending at all;
    /// without it, an overdue request that was never scheduled is skipped.
    static func plan(wanted: [Request], pending: [String: Date], delivered: Set<String>,
                     now: Date = .now, prefix: String = "timer-",
                     firesOverdue: Bool = true) -> (add: [Request], remove: [String]) {
        let wantedIDs = Set(wanted.map(\.id))
        let add = wanted.filter { request in
            guard !delivered.contains(request.id) else { return false }
            guard let scheduled = pending[request.id] else { return firesOverdue || request.fireDate > now }
            return request.fireDate > now && scheduled != request.fireDate
        }
        let remove = pending.keys.filter { $0.hasPrefix(prefix) && !wantedIDs.contains($0) }
        return (add, remove.sorted())
    }
}

/// When a medication's next dose is OK, and the reminder that says so. Mirrors upstream Baby
/// Buddy's `next_dose_time` (`time + next_dose_interval`), except that only the newest dose of each
/// medication per child counts: a later dose supersedes an earlier one's reminder.
enum MedicationReminderPolicy {
    static let enabledKey = "medicationRemindersEnabled"
    static var isEnabled: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["BB_DOSE_ALERT_SECONDS"] != nil { return true }
        #endif
        return SharedDefaults.suite.bool(forKey: enabledKey)
    }

    /// The intervals the editor offers before "Custom", in seconds.
    static let choices: [TimeInterval] = [14_400, 21_600, 28_800, 43_200, 86_400]

    /// When the dose after this one is OK, or `nil` if it has no interval.
    ///
    /// `BB_DOSE_ALERT_SECONDS=<n>` (DEBUG) turns the reminders on and shortens every interval to
    /// `n` seconds — the counterpart of the `BB_TIMER_ALERT_SECONDS` hook in
    /// ``ForgottenTimerPolicy/threshold(for:)``, because the shortest interval the editor offers is
    /// four hours and no test can wait for one.
    static func nextDose(after dose: LocalEntity) -> Date? {
        guard dose.kind == .medication,
              let raw = dose.payloadObject["next_dose_interval"] as? String,
              let interval = APIDuration.parse(raw), interval > 0 else { return nil }
        #if DEBUG
        if let seconds = ProcessInfo.processInfo.environment["BB_DOSE_ALERT_SECONDS"],
           let n = Double(seconds) {
            return dose.timestamp.addingTimeInterval(n)
        }
        #endif
        return dose.timestamp.addingTimeInterval(interval)
    }

    /// The newest dose of each medication per child, newest first. Names match case-insensitively.
    static func latestDoses(_ entities: [LocalEntity]) -> [LocalEntity] {
        var seen = Set<String>()
        return entities
            .filter { $0.kind == .medication && $0.syncState != .pendingDelete }
            .sorted { $0.timestamp > $1.timestamp }
            .filter { seen.insert("\($0.childID ?? 0)|\(normalizedName($0.payloadObject["name"] as? String))").inserted }
    }

    /// The newest dose of `name` for a child while its next dose is still ahead of `now` — what the
    /// editor warns about before another dose is logged.
    static func doseNotYetOK(named name: String, childID: Int, in entities: [LocalEntity],
                             now: Date = .now) -> (dose: LocalEntity, next: Date)? {
        let key = normalizedName(name)
        guard !key.isEmpty,
              let dose = latestDoses(entities).first(where: {
                  $0.childID == childID && normalizedName($0.payloadObject["name"] as? String) == key
              }),
              let next = nextDose(after: dose), next > now else { return nil }
        return (dose, next)
    }

    /// How doses are matched to one medicine: trimmed and case-insensitive.
    static func normalizedName(_ name: String?) -> String {
        (name ?? "").trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func identifier(for dose: LocalEntity) -> String { "medication-\(dose.localID.uuidString)" }

    /// The "next dose OK" notification for a dose, or `nil` if it has no interval.
    static func request(for dose: LocalEntity, childName: String?) -> ForgottenTimerPolicy.Request? {
        guard let fire = nextDose(after: dose) else { return nil }
        let name = dose.payloadObject["name"] as? String ?? "Medication"
        let owner = childName.map { "\($0)'s" } ?? "the"
        return ForgottenTimerPolicy.Request(
            id: identifier(for: dose),
            fireDate: fire,
            title: "\(name): next dose OK",
            body: "\(EntityFormatting.formatInterval(fire.timeIntervalSince(dose.timestamp))) since \(owner) "
                + "last dose at \(dose.timestamp.formatted(date: .omitted, time: .shortened)).",
            url: "babybuddy://dose/\(dose.localID.uuidString)")
    }
}

/// While a child is in sick mode and their newest reading is over the fever line, one reminder to
/// take the next reading, the check cadence after it. A newer reading replaces it.
enum TemperatureCheckPolicy {
    static func identifier(for reading: LocalEntity) -> String { "temperature-\(reading.localID.uuidString)" }

    /// `value` is the reading as the phone shows it, "100.8°F".
    static func request(for reading: LocalEntity, value: String, childName: String?,
                        hours: Int) -> ForgottenTimerPolicy.Request {
        let owner = childName.map { "\($0)'s" } ?? "the"
        return ForgottenTimerPolicy.Request(
            id: identifier(for: reading),
            fireDate: reading.timestamp.addingTimeInterval(Double(hours) * 3600),
            title: "Temperature check",
            body: "It's been \(hours) hr since \(owner) last reading (\(value)).",
            url: "babybuddy://home")
    }
}

/// Keeps the app's local notifications in step with the shared store: forgotten-timer alerts,
/// medication next-dose reminders and sick mode's temperature checks. Mirrors
/// ``LiveActivityManager``: one idempotent ``reconcile()`` that ``LiveActivityManager/reconcile()``
/// calls, so every timer start/stop/discard, editor save/delete and app foreground already covers
/// it; ``SyncEngine`` adds a pull that brought changes (a dose logged on the web).
@MainActor
final class LocalAlerts {
    static let shared = LocalAlerts()
    private let center = UNUserNotificationCenter.current()

    func reconcile() async {
        let timersOn = ForgottenTimerPolicy.isEnabled, dosesOn = MedicationReminderPolicy.isEnabled
        let checksOn = SickMode.checkHours > 0 && !SickModeStore.shared.active.isEmpty
        let wanted = timersOn || dosesOn || checksOn ? wantedRequests() : (timers: [], doses: [], checks: [])
        // The setting can arrive on before permission was ever asked (a restored App Group
        // default); ask now rather than schedule alerts that can never show. Temperature checks are
        // on by default, so they ask the first time one is due: sick mode on, with a fever.
        if timersOn || dosesOn || !wanted.checks.isEmpty,
           await center.notificationSettings().authorizationStatus == .notDetermined {
            _ = await requestAuthorization()
        }
        let pending = Dictionary(uniqueKeysWithValues: await center.pendingNotificationRequests()
            .compactMap { request -> (String, Date)? in
                guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                      let date = trigger.nextTriggerDate() else { return nil }
                return (request.identifier, date)
            })
        let delivered = Set(await center.deliveredNotifications().map(\.request.identifier))

        // A dose reminder or temperature check that is already overdue when first seen (an old
        // dose, or the app opened long after) says nothing useful, so only timers fire late.
        for (prefix, requests, firesOverdue) in [("timer-", timersOn ? wanted.timers : [], true),
                                                 ("medication-", dosesOn ? wanted.doses : [], false),
                                                 ("temperature-", wanted.checks, false)] {
            let plan = ForgottenTimerPolicy.plan(wanted: requests, pending: pending, delivered: delivered,
                                                 prefix: prefix, firesOverdue: firesOverdue)
            center.removePendingNotificationRequests(withIdentifiers: plan.remove)
            // A stopped timer's or superseded dose's delivered banner is stale too; a live one stays.
            let wantedIDs = Set(requests.map(\.id))
            center.removeDeliveredNotifications(withIdentifiers: delivered.filter {
                $0.hasPrefix(prefix) && !wantedIDs.contains($0)
            })
            for request in plan.add {
                let content = UNMutableNotificationContent()
                content.title = request.title
                content.body = request.body
                content.sound = .default
                content.userInfo = ["url": request.url]
                // A timer already past its threshold (app opened hours later) fires straight away.
                let fire = max(request.fireDate, Date().addingTimeInterval(1))
                let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: fire)
                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: request.id, content: content, trigger: trigger))
            }
        }
    }

    /// Ask for permission; returns whether alerts may be shown. Called from the Settings toggles.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// Every running timer, the newest dose of each medication, and the newest reading of each child
    /// in sick mode, in the shared store as wanted requests. Opens its own container, like the Live
    /// Activity manager, so widget-started timers are seen too.
    private func wantedRequests() -> (timers: [ForgottenTimerPolicy.Request], doses: [ForgottenTimerPolicy.Request],
                                      checks: [ForgottenTimerPolicy.Request]) {
        guard let container = try? ModelContainer(
            for: LocalStore.schema,
            configurations: ModelConfiguration(schema: LocalStore.schema, url: LocalStore.storeURL))
        else { return ([], [], []) }
        let context = ModelContext(container)
        func fetch(_ kind: String) -> [LocalEntity] {
            (try? context.fetch(FetchDescriptor<LocalEntity>(predicate: #Predicate { $0.kindRaw == kind }))) ?? []
        }
        let children = fetch("child")
        func firstName(_ childID: Int?) -> String? {
            let first = children.first { $0.serverID == childID }?.payloadObject["first_name"] as? String
            return first.flatMap { $0.isEmpty ? nil : $0 }
        }
        let timers = fetch("timer").filter(\.isRunningTimer).map {
            ForgottenTimerPolicy.request(for: $0, childName: firstName($0.childID))
        }
        let doses = MedicationReminderPolicy.latestDoses(fetch("medication")).compactMap {
            MedicationReminderPolicy.request(for: $0, childName: firstName($0.childID))
        }
        let hours = SickMode.checkHours, sick = SickModeStore.shared.active
        let unit = TemperatureUnit.current, line = SickMode.feverLine(in: unit)
        let readings = hours == 0 || sick.isEmpty ? [] : fetch("temperature").filter { $0.syncState != .pendingDelete }
        let checks = sick.keys.compactMap { child -> ForgottenTimerPolicy.Request? in
            let newest = readings.filter { $0.childID == child }.max { $0.timestamp < $1.timestamp }
            guard let newest, let reading = SickMode.readings([newest], unit: unit).first,
                  SickMode.isFever(reading.value, line: line) else { return nil }
            return TemperatureCheckPolicy.request(for: newest, value: unit.format(reading.value),
                                                  childName: firstName(child), hours: hours)
        }
        return (timers, doses, checks)
    }
}

/// Routes a tapped alert into the app through its deep link (a timer's Stop sheet, or a new dose
/// pre-filled from the last one) and lets one show as a banner while the app is in the foreground.
///
/// Main-actor isolated because UIKit finishes handling a response (a state-restoration snapshot)
/// when `didReceive` returns and asserts that happens on the main thread; nonisolated, the async
/// method returned on the cooperative pool and a tap that brought the app back from the background
/// crashed.
@MainActor
final class TimerAlertDelegate: NSObject, UNUserNotificationCenterDelegate {
    private let router: DeepLinkRouter
    init(router: DeepLinkRouter) { self.router = router }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound] // keep it in Notification Center if the banner is missed
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse) async {
        if let raw = response.notification.request.content.userInfo["url"] as? String, let url = URL(string: raw) {
            router.handle(url)
        }
    }
}

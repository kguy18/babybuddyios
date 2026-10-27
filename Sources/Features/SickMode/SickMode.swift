import Foundation
import Observation
import SwiftData

/// Sick mode turns Home into a dashboard for an ill child: temperatures, medicines with their
/// next-dose countdowns, today's diapers and fluids, and what's done and due.
///
/// It is local to this phone and per child. Nothing about it reaches the server: both parents'
/// phones read the same synced readings and doses, so each one prompts on its own. The rules here
/// are pure so they can be tested; ``SickModeStore`` holds the per-child state.
enum SickMode {
    // Settings ▸ Sick mode, in the App Group suite with the other settings. The keys are mirrored by
    // `@AppStorage` bindings in Settings.
    static let feverLineKey = "feverLineCelsius"
    static let suggestKey = "suggestSickMode"
    static let checkHoursKey = "temperatureCheckHours"

    /// The fever line is stored once, in Celsius, and shown in the phone's unit.
    static let defaultFeverLine = 38.0
    /// What Settings offers: 37.5 to 38.5 °C in tenths.
    static let feverLineChoices = (375...385).map { Double($0) / 10 }
    /// Hours between temperature-check reminders; 0 is off.
    static let checkHourChoices = [0, 2, 3, 4, 6]
    static let defaultCheckHours = 3

    static var feverLineCelsius: Double {
        SharedDefaults.suite.object(forKey: feverLineKey) as? Double ?? defaultFeverLine
    }

    /// Whether a reading over the line brings up the banner on Home.
    static var suggests: Bool { SharedDefaults.suite.object(forKey: suggestKey) as? Bool ?? true }

    static var checkHours: Int { SharedDefaults.suite.object(forKey: checkHoursKey) as? Int ?? defaultCheckHours }

    static func feverLine(in unit: TemperatureUnit) -> Double {
        unit.convert(feverLineCelsius, from: .celsius)
    }

    // MARK: Readings

    /// A temperature record with its value in the phone's unit.
    struct Reading {
        let entity: LocalEntity
        let value: Double
        var time: Date { entity.timestamp }
    }

    /// The temperature records among `entities`, in their given order, read in `unit`.
    static func readings(_ entities: [LocalEntity], unit: TemperatureUnit) -> [Reading] {
        entities.compactMap { entity in
            guard entity.kind == .temperature, let stored = entity.payloadObject["temperature"] as? Double
            else { return nil }
            return Reading(entity: entity, value: unit.reading(stored))
        }
    }

    /// The highest reading among `entities` as a Today tile shows it, "38.2°", or "—" with none.
    static func highestText(_ entities: [LocalEntity], unit: TemperatureUnit) -> String {
        readings(entities, unit: unit).map(\.value).max().map { TemperatureUnit.decimal($0) + "°" } ?? "—"
    }

    /// At or over the line. Compared in tenths, so 38.0 °C and 100.4 °F land on the same side.
    static func isFever(_ value: Double, line: Double) -> Bool {
        (value * 10).rounded() >= (line * 10).rounded()
    }

    /// The reading the Home banner offers sick mode for: the child's newest, when it is over the line
    /// and hasn't been dismissed. A newer reading over the line brings the banner back. `readings`
    /// are newest first.
    static func bannerReading(_ readings: [Reading], state: SickModeStore.ChildState,
                              line: Double) -> Reading? {
        guard state.startedAt == nil, let newest = readings.first, isFever(newest.value, line: line),
              newest.entity.localID != state.dismissedReading else { return nil }
        return newest
    }

    /// How the newest reading compares with the highest one in the six hours before it, or `nil`
    /// when there's nothing to compare. `readings` are newest first.
    static func trend(_ readings: [Reading]) -> (change: Double, since: Reading)? {
        guard let newest = readings.first else { return nil }
        let earlier = readings.dropFirst().filter { newest.time.timeIntervalSince($0.time) <= 6 * 3600 }
        guard let peak = earlier.max(by: { $0.value < $1.value }) else { return nil }
        return (((newest.value - peak.value) * 10).rounded() / 10, peak)
    }

    /// The first reading after the last one over the line: when the child came back under it.
    static func underSince(_ readings: [Reading], line: Double) -> Reading? {
        let lastFever = readings.firstIndex { isFever($0.value, line: line) } ?? readings.endIndex
        return lastFever > 0 ? readings[lastFever - 1] : nil
    }

    // MARK: Ending

    /// A day clear: no reading over the line and no dose for 24 hours, counted from no earlier than
    /// the start, so starting by hand doesn't ask to end at once. The newest reading must be under
    /// the line too, since a fever followed by a day of silence isn't a recovery.
    static func isClear(readings: [Reading], doses: [LocalEntity], startedAt: Date, line: Double,
                        now: Date) -> Bool {
        if let newest = readings.first, isFever(newest.value, line: line) { return false }
        let lastFever = readings.first { isFever($0.value, line: line) }?.time
        let clearSince = [startedAt, lastFever, doses.map(\.timestamp).max()].compactMap { $0 }.max()!
        return now.timeIntervalSince(clearSince) >= 86_400
    }

    /// The end prompt shows once the child is clear, unless "Keep it on" snoozed it.
    static func showsEndPrompt(clear: Bool, state: SickModeStore.ChildState, now: Date) -> Bool {
        clear && (state.keepOnUntil.map { now >= $0 } ?? true)
    }

    /// Calendar days since the start, counting the first as day 1.
    static func day(since start: Date, now: Date, calendar: Calendar = .current) -> Int {
        (calendar.dateComponents([.day], from: calendar.startOfDay(for: start),
                                 to: calendar.startOfDay(for: now)).day ?? 0) + 1
    }

    // MARK: Medicines

    /// One medicine dosed during sick mode: its newest dose and where the next one stands.
    struct Medicine {
        enum Phase: Equatable {
            /// The next dose has been OK since this time.
            case okNow(since: Date)
            /// The next dose is OK at `next`; `progress` is how much of the interval has passed.
            case waiting(next: Date, progress: Double)
            /// The dose has no next-dose interval.
            case noInterval
        }

        let dose: LocalEntity
        let name: String
        let phase: Phase
        /// Doses of this medicine in the 24 hours before now.
        let recentDoses: Int
    }

    /// One entry per medicine dosed since `start`, from ``MedicationReminderPolicy``'s newest dose of
    /// each: those OK now first, then the rest by soonest next dose.
    static func medicines(_ doses: [LocalEntity], since start: Date, now: Date) -> [Medicine] {
        func key(_ dose: LocalEntity) -> String {
            MedicationReminderPolicy.normalizedName(dose.payloadObject["name"] as? String)
        }
        return MedicationReminderPolicy.latestDoses(doses)
            .filter { $0.timestamp >= start }
            .map { dose -> Medicine in
                let phase: Medicine.Phase
                if let next = MedicationReminderPolicy.nextDose(after: dose) {
                    phase = next <= now ? .okNow(since: next)
                        : .waiting(next: next, progress: max(0, now.timeIntervalSince(dose.timestamp))
                                    / next.timeIntervalSince(dose.timestamp))
                } else {
                    phase = .noInterval
                }
                let recent = doses.filter {
                    key($0) == key(dose) && $0.timestamp <= now && now.timeIntervalSince($0.timestamp) < 86_400
                }
                let name = (dose.payloadObject["name"] as? String ?? "").trimmingCharacters(in: .whitespaces)
                return Medicine(dose: dose, name: name.isEmpty ? String(localized: "Medication") : name, phase: phase,
                                recentDoses: recent.count)
            }
            .sorted { order($0) < order($1) }
    }

    private static func order(_ medicine: Medicine) -> (Int, Date) {
        switch medicine.phase {
        case .okNow(let since): (0, since)
        case .waiting(let next, _): (1, next)
        case .noInterval: (2, medicine.dose.timestamp)
        }
    }

    // MARK: Wording

    /// "4:40 PM" today, "yesterday 4:40 PM", else "Mon 4:40 PM". `at` reads "yesterday at 4:40 PM".
    static func when(_ date: Date, at: Bool = false, now: Date = .now) -> String {
        let calendar = Calendar.current
        let time = (at ? String(localized: "at ") : "") + date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now).map { calendar.isDate(date, inSameDayAs: $0) }
        return String(localized: "\(yesterday == true ? String(localized: "yesterday") : date.formatted(.dateTime.weekday(.abbreviated))) \(time)")
    }

    /// "1 hr 10 min", "6 hr" or "25 min", rounded up to the minute as a countdown reads.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = max(1, Int((seconds / 60).rounded(.up)))
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return String(localized: "\(rest) min") }
        return rest == 0 ? String(localized: "\(hours) hr") : String(localized: "\(hours) hr \(rest) min")
    }
}

/// Sick mode's state for each child on this phone, in the App Group suite as one small JSON value.
@MainActor @Observable
final class SickModeStore {
    static let shared = SickModeStore()

    struct ChildState: Codable, Equatable {
        /// When sick mode started; `nil` while it's off.
        var startedAt: Date?
        /// The reading whose banner was closed, so only a newer one brings it back.
        var dismissedReading: UUID?
        /// "Keep it on" hides the end prompt until this time.
        var keepOnUntil: Date?
        /// The reading whose banner was last counted as shown.
        var bannerCounted: UUID?
        /// Which appearance of the end prompt was last counted: see ``SickModeStore/countEndPrompt(_:)``.
        var endPromptCounted: Date?
    }

    private static let key = "sickMode"
    @ObservationIgnored private let defaults: UserDefaults
    private var states: [Int: ChildState]

    init(defaults: UserDefaults = SharedDefaults.suite) {
        self.defaults = defaults
        states = defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([Int: ChildState].self, from: $0) } ?? [:]
    }

    subscript(child: Int) -> ChildState { states[child] ?? ChildState() }

    /// The children sick mode is on for, with when it started.
    var active: [Int: Date] { states.compactMapValues(\.startedAt) }

    func start(_ child: Int, at date: Date) {
        update(child) { $0.startedAt = date; $0.keepOnUntil = nil }
    }

    /// Turns sick mode off. The newest reading counts as dismissed, so a fever still on record
    /// doesn't bring the banner straight back.
    func end(_ child: Int, newestReading: UUID?) {
        update(child) {
            $0.startedAt = nil
            $0.keepOnUntil = nil
            if let newestReading { $0.dismissedReading = newestReading }
        }
    }

    func dismissBanner(_ child: Int, reading: UUID) {
        update(child) { $0.dismissedReading = reading }
    }

    func keepOn(_ child: Int, until date: Date) {
        update(child) { $0.keepOnUntil = date }
    }

    private func update(_ child: Int, _ change: (inout ChildState) -> Void) {
        change(&states[child, default: ChildState()])
        defaults.set(try? JSONEncoder().encode(states), forKey: Self.key)
    }
}

extension SickModeStore {
    /// Starting from the banner, "+" ▸ More… or Settings. A temperature check may now be due.
    func turnOn(_ child: Int, at date: Date, source: Analytics.SickModeStart) {
        resume(child, at: date)
        Analytics.sickModeStarted(source: source)
    }

    /// Ending from the prompt, Home or Settings, with a toast whose Undo restores the same start.
    func turnOff(_ child: Int, source: Analytics.SickModeEnd, in context: ModelContext) {
        guard let startedAt = self[child].startedAt else { return }
        let temperature = EntityKind.temperature.rawValue
        var newest = FetchDescriptor<LocalEntity>(
            predicate: #Predicate { $0.kindRaw == temperature && $0.childID == child },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        newest.fetchLimit = 1
        end(child, newestReading: (try? context.fetch(newest))?.first?.localID)
        Analytics.sickModeEnded(source: source)
        UndoToastCenter.shared.show(String(localized: "Sick mode ended")) {
            self.resume(child, at: startedAt)
            Analytics.sickModeEndUndone()
        }
        Task { await LocalAlerts.shared.reconcile() }
    }

    /// On again without counting a start: the Undo of an end.
    private func resume(_ child: Int, at date: Date) {
        start(child, at: date)
        Task { await LocalAlerts.shared.reconcile() }
    }

    /// The fever banner is on Home for `reading`. Counted once per reading, however often Home
    /// redraws or the app relaunches.
    func countBanner(_ child: Int, reading: UUID) {
        guard self[child].bannerCounted != reading else { return }
        update(child) { $0.bannerCounted = reading }
        Analytics.sickModeBannerShown()
    }

    /// The end prompt is on Home. Each appearance follows either the start or a "Keep it on", so
    /// that time names it, and the prompt is counted once per appearance.
    // ponytail: a prompt that goes, because of a later fever or dose, and comes back without a
    // "Keep it on" is counted once; key on the clear window's start if that ever matters.
    func countEndPrompt(_ child: Int) {
        let state = self[child]
        guard let appearance = state.keepOnUntil ?? state.startedAt,
              state.endPromptCounted != appearance else { return }
        update(child) { $0.endPromptCounted = appearance }
        Analytics.sickModeEndPromptShown()
    }
}

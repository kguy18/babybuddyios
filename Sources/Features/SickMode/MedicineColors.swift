import SwiftUI
import Observation

/// The six medicine colors, in the order they're handed out.
enum MedicineColor: Int, CaseIterable, Identifiable {
    case red, purple, pink, teal, olive, slate

    var id: Int { rawValue }
    var color: Color { BBColor.medicine[rawValue] }
    var name: String { [String(localized: "Red"), String(localized: "Purple"), String(localized: "Pink"), String(localized: "Teal"), String(localized: "Olive"), String(localized: "Slate")][rawValue] }

    /// The color for the `position`th medicine name, wrapping after six.
    init(position: Int) { self = Self.allCases[position % Self.allCases.count] }
}

/// Which color each medicine gets, on sick-mode surfaces.
///
/// Colors follow the order each medicine name first appears on the server, walking the cached doses
/// oldest first; names match the way ``MedicationReminderPolicy`` matches them. An assignment is
/// kept the first time it's made and never moved: the cache is windowed, so working the order out
/// again later would shift colors as old doses fall out of it. Both phones see the same records in
/// the same order, so they reach the same colors without syncing anything. A color changed by hand
/// is an override on this phone only.
@MainActor @Observable
final class MedicineColorStore {
    static let shared = MedicineColorStore()

    private static let assignedKey = "medicineColors.assigned"
    private static let overridesKey = "medicineColors.overrides"
    @ObservationIgnored private let defaults: UserDefaults
    /// Normalized names in the order they were first seen; each one's color is its position.
    private(set) var assigned: [String]
    private var overrides: [String: Int]

    init(defaults: UserDefaults = SharedDefaults.suite) {
        self.defaults = defaults
        assigned = defaults.stringArray(forKey: Self.assignedKey) ?? []
        overrides = defaults.dictionary(forKey: Self.overridesKey) as? [String: Int] ?? [:]
    }

    /// Give each name among `doses` that has no color yet the next one, oldest dose first.
    func assign(_ doses: [LocalEntity]) {
        var names = assigned
        var seen = Set(names)
        for dose in doses.sorted(by: { ($0.timestamp, $0.serverID ?? .max) < ($1.timestamp, $1.serverID ?? .max) }) {
            let name = MedicationReminderPolicy.normalizedName(dose.payloadObject["name"] as? String)
            if !name.isEmpty, seen.insert(name).inserted { names.append(name) }
        }
        guard names != assigned else { return }
        assigned = names
        defaults.set(names, forKey: Self.assignedKey)
    }

    /// The color the server order gives `name`, or the next one if it hasn't been seen yet.
    func serverColor(_ name: String) -> MedicineColor {
        MedicineColor(position: assigned.firstIndex(of: key(name)) ?? assigned.count)
    }

    /// The color to draw `name` in: this phone's choice, else the server's.
    func color(_ name: String) -> MedicineColor {
        overrides[key(name)].flatMap(MedicineColor.init(rawValue:)) ?? serverColor(name)
    }

    func isOverridden(_ name: String) -> Bool { overrides[key(name)] != nil }

    /// What the next medicine to appear will get.
    var next: MedicineColor { MedicineColor(position: assigned.count) }

    /// Picking the server's own color again clears the override.
    func set(_ color: MedicineColor, for name: String) {
        overrides[key(name)] = color == serverColor(name) ? nil : color.rawValue
        defaults.set(overrides, forKey: Self.overridesKey)
    }

    func resetOverrides() {
        overrides = [:]
        defaults.removeObject(forKey: Self.overridesKey)
    }

    private func key(_ name: String) -> String { MedicationReminderPolicy.normalizedName(name) }
}

import Foundation

enum GrowthReferenceSex: String, Codable, CaseIterable {
    case none, girls, boys
}

/// Optional display settings belong to one child on one device, not the API child schema.
struct GrowthProfile: Codable, Equatable {
    var sourceWeightUnit: GrowthWeightUnit = .kilograms
    var sourceLengthUnit: GrowthLengthUnit = .centimeters
    var displayWeightUnit: GrowthWeightUnit = .kilograms
    var unitsConfirmed = false
    var referenceSex: GrowthReferenceSex = .none
    var showWHO = false
    var chronologicalAgeConfirmed = false
    var useCorrectedAge = false
    var dueDateDocumented = false
    var dueDate = ""
    var lengthMethodConfirmed = false

    /// Corrected age is date minus a documented expected due date. Never inferred from weight,
    /// name, appearance, or age. Before that date there is no matching WHO reference age.
    func referenceBirthDate(birth: Date?, calendar: Calendar = .current) -> Date? {
        guard unitsConfirmed, showWHO, referenceSex != .none, let birth else { return nil }
        if useCorrectedAge {
            guard dueDateDocumented, let due = GrowthDate.parse(dueDate, calendar: calendar),
                  due > birth else { return nil }
            return due
        }
        return chronologicalAgeConfirmed ? birth : nil
    }

    func display(_ value: Double, metric: GrowthMetric) -> Double {
        guard unitsConfirmed else { return value }
        return metric == .weight ? displayWeightUnit.display(sourceWeightUnit.kilograms(value))
            : sourceLengthUnit.centimeters(value)
    }

    func referenceDisplay(_ value: Double, metric: GrowthMetric) -> Double {
        metric == .weight ? displayWeightUnit.display(value) : value
    }
}

enum GrowthProfileStore {
    private static func key(_ childID: Int) -> String { "growthChartProfile.\(childID)" }
    static func read(childID: Int, defaults: UserDefaults = .standard) -> GrowthProfile {
        guard let data = defaults.data(forKey: key(childID)),
              let profile = try? JSONDecoder().decode(GrowthProfile.self, from: data) else { return GrowthProfile() }
        return profile
    }
    static func write(_ profile: GrowthProfile, childID: Int, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        defaults.set(data, forKey: key(childID))
    }
    static func clear(defaults: UserDefaults = .standard) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("growthChartProfile.") {
            defaults.removeObject(forKey: key)
        }
    }
}

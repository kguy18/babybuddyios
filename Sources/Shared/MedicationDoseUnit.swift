import Foundation

/// Baby Buddy's medication API accepts these values, including an empty unit.
enum MedicationDoseUnit: String, CaseIterable {
    case unspecified = ""
    case milligrams = "mg"
    case milliliters = "ml"
    case tablets
    case drops

    static func editorValue(_ rawValue: String) -> String {
        // Some older client records used the display spelling instead of the API spelling.
        rawValue.caseInsensitiveCompare(Self.milliliters.rawValue) == .orderedSame
            ? Self.milliliters.rawValue : rawValue
    }

    static func options(including current: String) -> [String] {
        let supported = allCases.map(\.rawValue)
        // Keep an existing custom unit selected until the user deliberately changes it.
        return supported.contains(current) ? supported : supported + [current]
    }

    static func label(for rawValue: String) -> String {
        Self(rawValue: rawValue)?.label ?? rawValue
    }

    private var label: String {
        switch self {
        case .unspecified: return String(localized: "No unit")
        case .milligrams: return "mg"
        case .milliliters: return "mL"
        case .tablets: return String(localized: "Tablets")
        case .drops: return String(localized: "Drops")
        }
    }

    func format(_ dose: Double) -> String {
        let amount = dose.formatted(.number.grouping(.never).precision(.fractionLength(0...16)))
        switch self {
        case .unspecified:
            return amount
        case .milligrams, .milliliters:
            return String(localized: "\(amount) \(label)")
        case .tablets:
            if let count = Int(exactly: dose) { return String(localized: "\(count) tablets") }
            return String(localized: "\(amount) tablets")
        case .drops:
            if let count = Int(exactly: dose) { return String(localized: "\(count) drops") }
            return String(localized: "\(amount) drops")
        }
    }
}

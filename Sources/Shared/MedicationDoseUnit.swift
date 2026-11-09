import Foundation

/// The standard medication units, including an empty unit.
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

    static func options(including current: String, custom: [String] = []) -> [String] {
        let supported = allCases.map(\.rawValue) + custom
        // Keep an existing custom unit selected until the user deliberately changes it.
        return supported.contains(current) ? supported : supported + [current]
    }

    static func label(for rawValue: String) -> String {
        Self(rawValue: rawValue)?.label ?? rawValue
    }

    static func customValue(_ text: String, limit: Int) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.unicodeScalars.count <= limit,
              !value.unicodeScalars.contains(where: {
                  $0.properties.generalCategory == .control || CharacterSet.newlines.contains($0)
              }) else { return nil }
        return allCases.first { $0.rawValue.caseInsensitiveCompare(value) == .orderedSame }?.rawValue ?? value
    }

    static func format(_ dose: Double, rawValue: String) -> String {
        let raw = editorValue(rawValue)
        if let unit = Self(rawValue: raw) { return unit.format(dose) }
        let amount = formattedAmount(dose)
        return String(localized: "\(amount) \(raw)")
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
        let amount = Self.formattedAmount(dose)
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

    private static func formattedAmount(_ dose: Double) -> String {
        dose.formatted(.number.grouping(.never).precision(.fractionLength(0...16)))
    }
}

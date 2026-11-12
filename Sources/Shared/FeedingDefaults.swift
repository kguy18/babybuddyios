import Foundation

/// Preferences on this device, independent of the widget's one-tap logging settings.
/// Only type and method are reused. Amounts, times and notes always start fresh.
enum FeedingDefaults {
    enum Mode: String, CaseIterable, Identifiable {
        case app, fixed, remember
        var id: String { rawValue }
        var label: String {
            switch self {
            case .app: return String(localized: "App defaults")
            case .fixed: return String(localized: "My defaults")
            case .remember: return String(localized: "Last saved choices")
            }
        }
    }

    static let modeKey = "feedingDefaults.mode"
    static let typeKey = "feedingDefaults.type"
    static let methodKey = "feedingDefaults.method"

    static func choices(in defaults: UserDefaults = .standard) -> (type: FeedingType, method: FeedingMethod) {
        let mode = defaults.string(forKey: modeKey).flatMap(Mode.init(rawValue:)) ?? .app
        guard mode != .app else { return (.breastMilk, .leftBreast) }
        return (defaults.string(forKey: typeKey).flatMap(FeedingType.init(rawValue:)) ?? .breastMilk,
                defaults.string(forKey: methodKey).flatMap(FeedingMethod.init(rawValue:)) ?? .leftBreast)
    }

    /// Called only after saving a new feeding, including a converted timer, never on Cancel or edit.
    static func remember(type: FeedingType, method: FeedingMethod, in defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: modeKey) == Mode.remember.rawValue else { return }
        defaults.set(type.rawValue, forKey: typeKey)
        defaults.set(method.rawValue, forKey: methodKey)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        for key in [modeKey, typeKey, methodKey] { defaults.removeObject(forKey: key) }
    }
}

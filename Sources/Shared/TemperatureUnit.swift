import Foundation

/// The unit this phone shows temperatures in.
///
/// Baby Buddy stores a reading as a bare number, so the unit is a setting on each phone, and a
/// stored number is read by its range: under 50 is Celsius, over 80 is Fahrenheit, and anything
/// between is taken to be in this phone's unit. A °C phone and a °F phone can then share one server
/// and both show every reading correctly. New readings save in the phone's unit, as typed.
enum TemperatureUnit: String, CaseIterable {
    case fahrenheit, celsius

    /// The Settings choice, in the App Group suite so the widget formats readings the same way.
    /// Absent until someone picks a unit; until then the region decides.
    static let key = "temperatureUnit"

    static var current: TemperatureUnit {
        SharedDefaults.suite.string(forKey: key).flatMap(TemperatureUnit.init) ?? region
    }

    /// °F where the region measures in US units, °C everywhere else. `BB_TEMP_UNIT=c|f` (DEBUG)
    /// stands in for the region, so UI tests don't depend on the simulator's.
    static var region: TemperatureUnit {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["BB_TEMP_UNIT"] {
        case "c": return .celsius
        case "f": return .fahrenheit
        default: break
        }
        #endif
        return Locale.current.measurementSystem == .us ? .fahrenheit : .celsius
    }

    var symbol: String { self == .fahrenheit ? "°F" : "°C" }
    var name: String { self == .fahrenheit ? String(localized: "Fahrenheit") : String(localized: "Celsius") }

    /// The unit a stored number is in, going by its range.
    func unit(ofStored value: Double) -> TemperatureUnit {
        value < 50 ? .celsius : value > 80 ? .fahrenheit : self
    }

    /// A stored number as a reading in this unit, to one decimal.
    func reading(_ stored: Double) -> Double {
        convert(stored, from: unit(ofStored: stored))
    }

    /// `value`, measured in `unit`, in this unit to one decimal.
    func convert(_ value: Double, from unit: TemperatureUnit) -> Double {
        let converted = switch (unit, self) {
        case (.celsius, .fahrenheit): value * 9 / 5 + 32
        case (.fahrenheit, .celsius): (value - 32) * 5 / 9
        default: value
        }
        return (converted * 10).rounded() / 10
    }

    /// "100.8°F", "38.2°C".
    func format(_ value: Double) -> String { Self.decimal(value) + symbol }

    /// One decimal, no unit: "100.8", "38.0".
    static func decimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1)).grouping(.never)) }
}

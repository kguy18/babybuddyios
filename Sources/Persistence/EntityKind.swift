import Foundation

/// The Baby Buddy record types the app caches and syncs. Each kind knows its API path
/// and which payload field carries its primary timestamp / child reference, so the
/// generic cache + sync layers can treat every record uniformly.
enum EntityKind: String, Codable, CaseIterable, Identifiable {
    case child
    case feeding
    case change
    case sleep
    case tummyTime
    case pumping
    case note
    case timer
    case weight
    case height
    case headCircumference
    case temperature
    case bmi
    case medication

    var id: String { rawValue }

    /// Collection path under `/api/`.
    var path: String {
        switch self {
        case .child: return "children"
        case .feeding: return "feedings"
        case .change: return "changes"
        case .sleep: return "sleep"
        case .tummyTime: return "tummy-times"
        case .pumping: return "pumping"
        case .note: return "notes"
        case .timer: return "timers"
        case .weight: return "weight"
        case .height: return "height"
        case .headCircumference: return "head-circumference"
        case .temperature: return "temperature"
        case .bmi: return "bmi"
        case .medication: return "medications"
        }
    }

    /// The payload key holding the record's primary timestamp, used for timeline sorting
    /// and `date_min`/`date_max` pull windows.
    var timeField: String {
        switch self {
        case .feeding, .sleep, .tummyTime, .pumping, .timer: return "start"
        case .change, .note, .temperature, .medication: return "time"
        case .weight, .height, .headCircumference, .bmi: return "date"
        case .child: return "birth_date"
        }
    }

    var displayName: String {
        switch self {
        case .child: return "Child"
        case .feeding: return "Feeding"
        case .change: return "Diaper Change"
        case .sleep: return "Sleep"
        case .tummyTime: return "Tummy Time"
        case .pumping: return "Pumping"
        case .note: return "Note"
        case .timer: return "Timer"
        case .weight: return "Weight"
        case .height: return "Height"
        case .headCircumference: return "Head Circumference"
        case .temperature: return "Temperature"
        case .bmi: return "BMI"
        case .medication: return "Medication"
        }
    }

    var systemImage: String {
        switch self {
        case .child: return "person.crop.circle"
        case .feeding: return "drop.fill"
        case .change: return "arrow.triangle.2.circlepath"
        case .sleep: return "moon.fill"
        case .tummyTime: return "figure.and.child.holdinghands"
        case .pumping: return "waveform.path"
        case .note: return "note.text"
        case .timer: return "timer"
        case .weight: return "scalemass"
        case .height: return "ruler"
        case .headCircumference: return "circle.dashed"
        case .temperature: return "thermometer.medium"
        case .bmi: return "chart.bar"
        case .medication: return "pills.fill"
        }
    }

    /// Kinds shown in the merged activity timeline (excludes Child, which is metadata).
    static var timelineKinds: [EntityKind] {
        [.feeding, .change, .sleep, .tummyTime, .pumping, .note, .temperature,
         .medication, .weight, .height, .headCircumference, .bmi]
    }

    // MARK: Payload extraction

    /// Extract the sortable timestamp from a raw JSON payload.
    func timestamp(from payload: [String: Any]) -> Date {
        if let raw = payload[timeField] as? String, let date = APIDate.parse(raw) {
            return date
        }
        return .distantPast
    }

    /// Extract the child id from a raw JSON payload (nil for unassigned timers).
    func childID(from payload: [String: Any]) -> Int? {
        payload["child"] as? Int
    }
}

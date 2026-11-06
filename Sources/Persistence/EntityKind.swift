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
        case .medication: return "medication"
        }
    }

    /// The payload key holding the record's primary timestamp, used for timeline sorting
    /// and as the `ordering` field on list requests.
    var timeField: String {
        switch self {
        case .feeding, .sleep, .tummyTime, .pumping, .timer: return "start"
        case .change, .note, .temperature, .medication: return "time"
        case .weight, .height, .headCircumference, .bmi: return "date"
        case .child: return "birth_date"
        }
    }

    /// Whether bulk pulls window this kind to a rolling date range (and so support on-demand
    /// "load older" paging). Children and timers are low-volume metadata; the growth
    /// measurements are infrequent *and* the API exposes no range filter for them
    /// (`filterset_fields = ("child", "date")` — exact match only), so all four are always
    /// pulled in full. The remaining high-volume event kinds are windowed.
    var isWindowed: Bool {
        switch self {
        case .feeding, .change, .sleep, .tummyTime, .pumping, .note, .temperature, .medication:
            return true
        case .child, .timer, .weight, .height, .headCircumference, .bmi:
            return false
        }
    }

    /// The query-parameter base name for range-filtering this kind on the Baby Buddy API:
    /// the filter is `<base>_min`/`<base>_max` (both `IsoDateTimeFilter`, gte/lte). Start/end
    /// events filter on `start`; time-stamped records (changes/notes/temperature/medications)
    /// expose `date_min`/`date_max` mapped onto their `time` field — i.e. the filter base is
    /// *not* always `timeField`. Only meaningful when ``isWindowed``. Verified against
    /// upstream `api/filters.py` (`StartEndFieldFilter` / `TimeFieldFilter`).
    var rangeFilterParam: String {
        timeField == "start" ? "start" : "date"
    }

    var displayName: String {
        switch self {
        case .child: return String(localized: "Child")
        case .feeding: return String(localized: "Feeding")
        case .change: return String(localized: "Diaper Change")
        case .sleep: return String(localized: "Sleep")
        case .tummyTime: return String(localized: "Tummy Time")
        case .pumping: return String(localized: "Pumping")
        case .note: return String(localized: "Note")
        case .timer: return String(localized: "Timer")
        case .weight: return String(localized: "Weight")
        case .height: return String(localized: "Height")
        case .headCircumference: return String(localized: "Head Circumference")
        case .temperature: return String(localized: "Temperature")
        case .bmi: return String(localized: "BMI")
        case .medication: return String(localized: "Medication")
        }
    }

    var sentenceName: String {
        switch self {
        case .child: return String(localized: "child")
        case .feeding: return String(localized: "feeding")
        case .change: return String(localized: "diaper change")
        case .sleep: return String(localized: "sleep")
        case .tummyTime: return String(localized: "tummy time")
        case .pumping: return String(localized: "pumping")
        case .note: return String(localized: "note")
        case .timer: return String(localized: "timer")
        case .weight: return String(localized: "weight")
        case .height: return String(localized: "height")
        case .headCircumference: return String(localized: "head circumference")
        case .temperature: return String(localized: "temperature")
        case .bmi: return String(localized: "bmi")
        case .medication: return String(localized: "medication")
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

    /// The multipart file-upload field for this kind's image, if it has one. Baby Buddy exposes
    /// a note `image` and a child `picture` (both Django `ImageField`s); no other kind has media.
    var imageField: String? {
        switch self {
        case .note: return "image"
        case .child: return "picture"
        default: return nil
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

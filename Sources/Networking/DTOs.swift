import Foundation

// MARK: - Resource protocol

/// A Baby Buddy API resource. `path` is the collection path under `/api/`.
protocol APIResource: Codable, Identifiable {
    static var path: String { get }
    var id: Int? { get }
}

// MARK: - Paged list envelope

/// DRF's paginated list response.
struct Paged<T: Codable>: Codable {
    let count: Int
    let next: String?
    let previous: String?
    let results: [T]
}

// MARK: - Enums

enum FeedingType: String, Codable, CaseIterable, Identifiable {
    case breastMilk = "breast milk"
    case formula = "formula"
    case fortifiedBreastMilk = "fortified breast milk"
    case solidFood = "solid food"
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum FeedingMethod: String, Codable, CaseIterable, Identifiable {
    case bottle = "bottle"
    case leftBreast = "left breast"
    case rightBreast = "right breast"
    case bothBreasts = "both breasts"
    case parentFed = "parent fed"
    case selfFed = "self fed"
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum DiaperColor: String, Codable, CaseIterable, Identifiable {
    case black, brown, green, yellow
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

// MARK: - Resources
//
// Each DTO carries the full set of serializer fields. Read-only fields (`id`,
// `duration`, `slug`, `picture`) are optional so the same struct can also be encoded
// for writes — DRF silently ignores read-only fields on input. `timer` is write-only
// and only set when converting a stopped timer into an entry.

struct ChildDTO: APIResource {
    static let path = "children"
    var id: Int?
    var first_name: String
    var last_name: String
    var birth_date: Date
    var birth_time: Date?
    var slug: String?
    var picture: String?

    var displayName: String { [first_name, last_name].filter { !$0.isEmpty }.joined(separator: " ") }
}

struct FeedingDTO: APIResource {
    static let path = "feedings"
    var id: Int?
    var child: Int
    var start: Date
    var end: Date
    var duration: String?
    var type: FeedingType
    var method: FeedingMethod
    var amount: Double?
    var notes: String?
    var tags: [String]?
    var timer: Int?
}

struct DiaperChangeDTO: APIResource {
    static let path = "changes"
    var id: Int?
    var child: Int
    var time: Date
    var wet: Bool?
    var solid: Bool?
    var color: DiaperColor?
    var amount: Double?
    var notes: String?
    var tags: [String]?
}

struct SleepDTO: APIResource {
    static let path = "sleep"
    var id: Int?
    var child: Int
    var start: Date
    var end: Date
    var duration: String?
    var nap: Bool?
    var notes: String?
    var tags: [String]?
    var timer: Int?
}

struct TummyTimeDTO: APIResource {
    static let path = "tummy-times"
    var id: Int?
    var child: Int
    var start: Date
    var end: Date
    var duration: String?
    var milestone: String?
    var tags: [String]?
    var timer: Int?
}

struct PumpingDTO: APIResource {
    static let path = "pumping"
    var id: Int?
    var child: Int
    var start: Date
    var end: Date
    var duration: String?
    var amount: Double?
    var notes: String?
    var tags: [String]?
    var timer: Int?
}

struct NoteDTO: APIResource {
    static let path = "notes"
    var id: Int?
    var child: Int
    var note: String
    var time: Date
    var tags: [String]?
}

struct TimerDTO: APIResource {
    static let path = "timers"
    var id: Int?
    var child: Int?
    var name: String?
    var start: Date
    var duration: String?
    var user: Int?
}

struct WeightDTO: APIResource {
    static let path = "weight"
    var id: Int?
    var child: Int
    var weight: Double
    var date: Date
    var notes: String?
    var tags: [String]?
}

struct HeightDTO: APIResource {
    static let path = "height"
    var id: Int?
    var child: Int
    var height: Double
    var date: Date
    var notes: String?
    var tags: [String]?
}

struct HeadCircumferenceDTO: APIResource {
    static let path = "head-circumference"
    var id: Int?
    var child: Int
    var head_circumference: Double
    var date: Date
    var notes: String?
    var tags: [String]?
}

struct TemperatureDTO: APIResource {
    static let path = "temperature"
    var id: Int?
    var child: Int
    var temperature: Double
    var time: Date
    var notes: String?
    var tags: [String]?
}

struct BMIDTO: APIResource {
    static let path = "bmi"
    var id: Int?
    var child: Int
    var bmi: Double
    var date: Date
    var notes: String?
    var tags: [String]?
}

struct MedicationDTO: APIResource {
    static let path = "medication"
    var id: Int?
    var child: Int
    var name: String
    var dosage: Double?
    var dosage_unit: String?
    var time: Date
    var next_dose_interval: String?
    var notes: String?
    var tags: [String]?
}

struct TagDTO: Codable, Identifiable, Hashable {
    var slug: String?
    var name: String
    var color: String?
    var last_used: Date?
    var id: String { slug ?? name }
}

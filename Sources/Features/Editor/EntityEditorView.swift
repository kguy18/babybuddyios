import SwiftUI
import SwiftData

/// Adaptive create/edit form for any ``EntityKind``. Reads/writes a JSON payload through
/// ``LocalRepository`` and triggers a sync on save. Renders only the fields relevant to
/// the kind being edited.
struct EntityEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss

    let kind: EntityKind
    let childID: Int
    /// nil → creating a new record; non-nil → editing.
    var entity: LocalEntity?
    /// Set when this editor is converting a running timer into an activity. Pre-fills
    /// start = timer.start, end = now, and routes Save through ``LocalRepository/convertTimer``.
    var sourceTimer: LocalEntity?

    // Common fields
    @State private var start = Date()
    @State private var end = Date()
    @State private var time = Date()
    @State private var date = Date()
    @State private var notes = ""
    @State private var tagNames: [String] = []
    // Feeding
    @State private var feedingType: FeedingType = .breastMilk
    @State private var feedingMethod: FeedingMethod = .leftBreast
    @State private var amount = ""
    // Diaper
    @State private var wet = true
    @State private var solid = false
    @State private var color: DiaperColor?
    // Sleep / tummy time
    @State private var nap = false
    @State private var milestone = ""
    // Note
    @State private var noteText = ""
    // Measurement
    @State private var value = ""
    // Medication
    @State private var medName = ""
    @State private var dosage = ""
    @State private var dosageUnit = "mg"

    private var isEditing: Bool { entity != nil }
    private var isConverting: Bool { sourceTimer != nil }

    private var navTitle: String {
        if isConverting { return "Convert to \(kind.displayName)" }
        return "\(isEditing ? "Edit" : "New") \(kind.displayName)"
    }

    var body: some View {
        NavigationStack {
            Form { fields }
                .navigationTitle(navTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save).disabled(!isValid)
                    }
                }
                .onAppear(perform: populate)
        }
    }

    // MARK: Field sections

    @ViewBuilder private var fields: some View {
        switch kind {
        case .feeding:
            startEndSection
            Section {
                Picker("Type", selection: $feedingType) {
                    ForEach(FeedingType.allCases) { Text($0.label).tag($0) }
                }
                Picker("Method", selection: $feedingMethod) {
                    ForEach(FeedingMethod.allCases) { Text($0.label).tag($0) }
                }
                amountField
            }
            notesSection; tagsSection
        case .change:
            Section { DatePicker("Time", selection: $time) }
            Section {
                Toggle("Wet", isOn: $wet)
                Toggle("Solid", isOn: $solid)
                Picker("Color", selection: $color) {
                    Text("None").tag(DiaperColor?.none)
                    ForEach(DiaperColor.allCases) { Text($0.label).tag(DiaperColor?.some($0)) }
                }
            }
            notesSection; tagsSection
        case .sleep:
            startEndSection
            Section { Toggle("Nap", isOn: $nap) }
            notesSection; tagsSection
        case .tummyTime:
            startEndSection
            Section { TextField("Milestone", text: $milestone) }
            tagsSection
        case .pumping:
            startEndSection
            Section { amountField }
            notesSection; tagsSection
        case .note:
            Section { DatePicker("Time", selection: $time) }
            Section { TextField("Note", text: $noteText, axis: .vertical).lineLimit(3...8) }
            tagsSection
        case .weight, .height, .headCircumference, .bmi:
            Section {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField(measurementLabel, text: $value).keyboardType(.decimalPad)
            }
            notesSection; tagsSection
        case .temperature:
            Section {
                DatePicker("Time", selection: $time)
                TextField("Temperature", text: $value).keyboardType(.decimalPad)
            }
            notesSection; tagsSection
        case .medication:
            Section {
                DatePicker("Time", selection: $time)
                TextField("Name", text: $medName)
                TextField("Dosage", text: $dosage).keyboardType(.decimalPad)
                TextField("Unit", text: $dosageUnit)
            }
            notesSection; tagsSection
        case .timer, .child:
            Text("Not editable here.")
        }
    }

    private var startEndSection: some View {
        Section {
            DatePicker("Start", selection: $start)
            DatePicker("End", selection: $end)
        } footer: {
            if end > start {
                Text("Duration: \(EntityFormatting.formatInterval(end.timeIntervalSince(start)))")
            }
        }
    }

    private var amountField: some View {
        TextField("Amount (ml)", text: $amount).keyboardType(.decimalPad)
    }

    private var notesSection: some View {
        Section { TextField("Notes", text: $notes, axis: .vertical).lineLimit(1...4) }
    }

    private var tagsSection: some View {
        Section("Tags") {
            TagField(selected: $tagNames)
        }
    }

    private var measurementLabel: String {
        switch kind {
        case .weight: return "Weight"
        case .height: return "Height"
        case .headCircumference: return "Head circumference"
        case .bmi: return "BMI"
        default: return "Value"
        }
    }

    // MARK: Validation

    private var isValid: Bool {
        switch kind {
        case .feeding, .sleep, .tummyTime, .pumping: return end >= start
        case .note: return !noteText.trimmingCharacters(in: .whitespaces).isEmpty
        case .weight, .height, .headCircumference, .bmi, .temperature: return Double(value) != nil
        case .medication: return !medName.trimmingCharacters(in: .whitespaces).isEmpty
        default: return true
        }
    }

    // MARK: Load / save

    private func populate() {
        if let timer = sourceTimer, entity == nil {
            // Converting: inherit the timer's start, end the activity now.
            if let s = timer.payloadObject["start"] as? String, let d = APIDate.parse(s) { start = d }
            end = Date()
            return
        }
        guard let p = entity?.payloadObject else { return }
        func parseDate(_ key: String) -> Date? { (p[key] as? String).flatMap(APIDate.parse) }
        start = parseDate("start") ?? start
        end = parseDate("end") ?? end
        time = parseDate("time") ?? time
        date = parseDate("date") ?? date
        notes = p["notes"] as? String ?? ""
        tagNames = (p["tags"] as? [String]) ?? []
        if let t = p["type"] as? String, let ft = FeedingType(rawValue: t) { feedingType = ft }
        if let m = p["method"] as? String, let fm = FeedingMethod(rawValue: m) { feedingMethod = fm }
        if let a = p["amount"] as? Double { amount = trimmed(a) }
        wet = p["wet"] as? Bool ?? wet
        solid = p["solid"] as? Bool ?? solid
        if let c = p["color"] as? String { color = DiaperColor(rawValue: c) }
        nap = p["nap"] as? Bool ?? nap
        milestone = p["milestone"] as? String ?? ""
        noteText = p["note"] as? String ?? ""
        medName = p["name"] as? String ?? ""
        if let d = p["dosage"] as? Double { dosage = trimmed(d) }
        dosageUnit = p["dosage_unit"] as? String ?? dosageUnit
        for key in ["weight", "height", "head_circumference", "bmi", "temperature"] {
            if let v = p[key] as? Double { value = trimmed(v) }
        }
    }

    private func save() {
        let payload = buildPayload()
        let repo = LocalRepository(context: context)
        if let sourceTimer {
            repo.convertTimer(sourceTimer, to: kind, payload: payload)
        } else if let entity {
            repo.update(entity, payload: payload)
        } else {
            repo.create(kind: kind, payload: payload)
        }
        Task { await sync.sync() }
        dismiss()
    }

    private func buildPayload() -> [String: Any] {
        var p: [String: Any] = ["child": childID]
        let tagList = tagNames
        func iso(_ d: Date) -> String { APIDate.isoDateTime.string(from: d) }

        switch kind {
        case .feeding:
            p["start"] = iso(start); p["end"] = iso(end)
            p["type"] = feedingType.rawValue; p["method"] = feedingMethod.rawValue
            if let a = Double(amount) { p["amount"] = a }
            p["notes"] = notes; p["tags"] = tagList
        case .change:
            p["time"] = iso(time); p["wet"] = wet; p["solid"] = solid
            if let color { p["color"] = color.rawValue }
            p["notes"] = notes; p["tags"] = tagList
        case .sleep:
            p["start"] = iso(start); p["end"] = iso(end); p["nap"] = nap
            p["notes"] = notes; p["tags"] = tagList
        case .tummyTime:
            p["start"] = iso(start); p["end"] = iso(end)
            p["milestone"] = milestone; p["tags"] = tagList
        case .pumping:
            p["start"] = iso(start); p["end"] = iso(end)
            if let a = Double(amount) { p["amount"] = a }
            p["notes"] = notes; p["tags"] = tagList
        case .note:
            p["time"] = iso(time); p["note"] = noteText; p["tags"] = tagList
        case .weight, .height, .headCircumference, .bmi:
            let key = ["weight": "weight", "height": "height",
                       "headCircumference": "head_circumference", "bmi": "bmi"][kind.rawValue]!
            p[key] = Double(value) ?? 0
            p["date"] = APIDate.dateOnly.string(from: date)
            p["notes"] = notes; p["tags"] = tagList
        case .temperature:
            p["temperature"] = Double(value) ?? 0; p["time"] = iso(time)
            p["notes"] = notes; p["tags"] = tagList
        case .medication:
            p["name"] = medName; p["time"] = iso(time)
            if let d = Double(dosage) { p["dosage"] = d }
            p["dosage_unit"] = dosageUnit
            p["notes"] = notes; p["tags"] = tagList
        case .timer, .child:
            break
        }
        // Preserve the server id when editing so the payload round-trips.
        if let id = entity?.serverID { p["id"] = id }
        return p
    }

    private func trimmed(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }
}

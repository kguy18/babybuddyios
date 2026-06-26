import SwiftUI
import SwiftData

/// Adaptive create/edit form for any ``EntityKind``. Reads/writes a JSON payload through
/// ``LocalRepository`` and triggers a sync on save. Renders only the fields relevant to
/// the kind being edited, styled to the Baby Buddy design system (grouped white cards on a
/// soft surface, tinted activity pills, value-pill time fields, brand-blue tag autocomplete).
struct EntityEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncEngine.self) private var sync
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    let childID: Int
    /// nil → creating a new record; non-nil → editing.
    let entity: LocalEntity?
    /// Set when this editor is converting a running timer into an activity. Pre-fills
    /// start = timer.start, end = now, and routes Save through ``LocalRepository/convertTimer``.
    let sourceTimer: LocalEntity?

    /// The record kind. Mirrored into state so the top activity selector can swap it while
    /// creating; locked to the passed-in value when editing or converting.
    @State private var kind: EntityKind

    init(kind: EntityKind, childID: Int, entity: LocalEntity? = nil, sourceTimer: LocalEntity? = nil) {
        self.childID = childID
        self.entity = entity
        self.sourceTimer = sourceTimer
        _kind = State(initialValue: kind)
    }

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

    @State private var confirmingDelete = false

    private var isEditing: Bool { entity != nil }
    private var isConverting: Bool { sourceTimer != nil }

    private var navTitle: String {
        if isConverting { return "Convert to \(kind.displayName)" }
        return "\(isEditing ? "Edit" : "New") \(kind.displayName)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if kind == .timer || kind == .child {
                        Text("Not editable here.").foregroundStyle(.secondary)
                    } else {
                        if showsActivitySelector { activitySelector }
                        sectioned("When") { whenCard }
                        sectioned(detailsTitle) { detailsCard }
                        sectioned("Tags") { tagsCard }
                        if showsNotes { sectioned("Notes") { notesCard } }
                        actionButtons.padding(.top, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 28)
            }
            .background(BBColor.surface)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isValid).tint(BBColor.brandAccent)
                }
            }
            .confirmationDialog("Delete this \(kind.displayName.lowercased())?",
                                isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive, action: delete)
            }
            .onAppear(perform: populate)
        }
    }

    // MARK: Layout helpers

    private func sectioned<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title)
            content()
        }
    }

    private var rowDivider: some View {
        Rectangle().fill(BBColor.divider).frame(height: 0.5).padding(.leading, 15)
    }

    // MARK: Activity selector

    private let quickKinds: [EntityKind] = [.feeding, .change, .sleep, .tummyTime, .pumping, .note]
    private var showsActivitySelector: Bool {
        !isEditing && !isConverting && quickKinds.contains(kind)
    }

    private var activitySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(quickKinds) { activityPill($0) }
            }
            .padding(.horizontal, 2)
        }
    }

    private func activityPill(_ k: EntityKind) -> some View {
        let selected = k == kind
        let accent = BBColor.activity(k)
        return HStack(spacing: 6) {
            k.icon(15)
            Text(shortName(k)).font(.subheadline.weight(selected ? .semibold : .medium))
        }
        .foregroundStyle(selected ? Color.white : accent)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background {
            Capsule().fill(selected ? accent : accent.opacity(scheme == .dark ? 0.22 : 0.15))
        }
        .contentShape(Capsule())
        .onTapGesture { withAnimation(.snappy(duration: 0.2)) { kind = k } }
    }

    private func shortName(_ k: EntityKind) -> String {
        switch k {
        case .feeding: return "Feeding"
        case .change: return "Diaper"
        case .sleep: return "Sleep"
        case .tummyTime: return "Tummy"
        case .pumping: return "Pump"
        case .note: return "Note"
        default: return k.displayName
        }
    }

    // MARK: When card

    private var whenCard: some View {
        BBCard(cornerRadius: BBRadius.tile, padding: 0) {
            VStack(spacing: 0) {
                switch kind {
                case .feeding, .sleep, .tummyTime, .pumping:
                    pickerRow("Start", selection: $start, components: [.date, .hourAndMinute])
                    rowDivider
                    endRow
                case .change, .note, .temperature, .medication:
                    pickerRow("Time", selection: $time, components: [.date, .hourAndMinute])
                case .weight, .height, .headCircumference, .bmi:
                    pickerRow("Date", selection: $date, components: .date)
                case .timer, .child:
                    EmptyView()
                }
            }
        }
    }

    private func pickerRow(_ label: String, selection: Binding<Date>,
                           components: DatePickerComponents) -> some View {
        HStack {
            Text(label).font(.body)
            Spacer()
            DatePicker("", selection: selection, displayedComponents: components)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(BBColor.brandAccent)
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    private var endRow: some View {
        HStack {
            Text("End").font(.body)
            Spacer()
            if end > start {
                Text(EntityFormatting.formatInterval(end.timeIntervalSince(start)))
                    .font(.caption).foregroundStyle(.tertiary).monospacedDigit()
            }
            DatePicker("", selection: $end, displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(BBColor.brandAccent)
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    // MARK: Details card (type-specific)

    private var detailsTitle: String { kind == .note ? "Note" : "Details" }

    @ViewBuilder private var detailsCard: some View {
        switch kind {
        case .feeding: feedingDetails
        case .change: changeDetails
        case .sleep:
            BBCard(cornerRadius: BBRadius.tile, padding: 0) { toggleRow("Nap", isOn: $nap) }
        case .tummyTime:
            BBCard(cornerRadius: BBRadius.tile) {
                TextField("Milestone", text: $milestone, axis: .vertical).lineLimit(1...3)
            }
        case .pumping:
            BBCard(cornerRadius: BBRadius.tile) { fieldLabeled("Amount") { amountStepper } }
        case .note:
            BBCard(cornerRadius: BBRadius.tile) {
                TextField("Add a note…", text: $noteText, axis: .vertical)
                    .lineLimit(3...8)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            }
        case .weight, .height, .headCircumference, .bmi:
            BBCard(cornerRadius: BBRadius.tile) {
                fieldLabeled(measurementLabel) { numericField(text: $value, unit: nil) }
            }
        case .temperature:
            BBCard(cornerRadius: BBRadius.tile) {
                fieldLabeled("Temperature") { numericField(text: $value, unit: "°") }
            }
        case .medication:
            medicationDetails
        case .timer, .child:
            EmptyView()
        }
    }

    private var feedingDetails: some View {
        BBCard(cornerRadius: BBRadius.tile) {
            VStack(alignment: .leading, spacing: 16) {
                fieldLabeled("Type") {
                    BBSegmentedControl(selection: $feedingType,
                                       options: FeedingType.allCases) { $0.shortLabel }
                }
                fieldLabeled("Method") {
                    menuField(options: FeedingMethod.allCases, selection: $feedingMethod) { $0.label }
                }
                fieldLabeled("Amount") { amountStepper }
            }
        }
    }

    private var changeDetails: some View {
        BBCard(cornerRadius: BBRadius.tile, padding: 0) {
            VStack(spacing: 0) {
                toggleRow("Wet", isOn: $wet)
                rowDivider
                toggleRow("Solid", isOn: $solid)
                rowDivider
                colorRow
            }
        }
    }

    private var medicationDetails: some View {
        BBCard(cornerRadius: BBRadius.tile) {
            VStack(alignment: .leading, spacing: 16) {
                fieldLabeled("Name") { plainField("Name", text: $medName) }
                fieldLabeled("Dosage") {
                    HStack(spacing: 10) {
                        numericField(text: $dosage, unit: nil)
                        plainField("Unit", text: $dosageUnit).frame(width: 92)
                    }
                }
            }
        }
    }

    // MARK: Field building blocks

    private func fieldLabeled<V: View>(_ label: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.footnote).foregroundStyle(.secondary)
            content()
        }
    }

    private func toggleRow(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) { Text(label).font(.body) }
            .tint(BBColor.primary)
            .padding(.horizontal, 15).padding(.vertical, 7)
    }

    private var colorRow: some View {
        HStack {
            Text("Color").font(.body)
            Spacer()
            Menu {
                Button { color = nil } label: { menuLabel("None", checked: color == nil) }
                ForEach(DiaperColor.allCases, id: \.self) { c in
                    Button { color = c } label: { menuLabel(c.label, checked: color == c) }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(color?.label ?? "None")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .foregroundStyle(BBColor.brandAccent)
            }
        }
        .padding(.horizontal, 15).padding(.vertical, 11)
    }

    private func menuField<T: Hashable>(options: [T], selection: Binding<T>,
                                        label: @escaping (T) -> String) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button { selection.wrappedValue = option } label: {
                    menuLabel(label(option), checked: option == selection.wrappedValue)
                }
            }
        } label: {
            HStack {
                Text(label(selection.wrappedValue)).font(.body)
                Spacer()
                Image(systemName: "chevron.up.chevron.down").font(.caption2)
            }
            .foregroundStyle(BBColor.brandAccent)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BBColor.nested, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(BBColor.fieldStroke, lineWidth: 0.5)
            }
        }
    }

    @ViewBuilder private func menuLabel(_ title: String, checked: Bool) -> some View {
        if checked { Label(title, systemImage: "checkmark") } else { Text(title) }
    }

    private func plainField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(BBColor.nested, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(BBColor.fieldStroke, lineWidth: 0.5)
            }
    }

    /// An inset numeric input with a large tabular figure and optional unit suffix.
    private func numericField(text: Binding<String>, unit: String?) -> some View {
        HStack(spacing: 6) {
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .font(.title3.weight(.semibold)).monospacedDigit()
            if let unit { Text(unit).font(.subheadline).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(BBColor.nested, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(BBColor.fieldStroke, lineWidth: 0.5)
        }
    }

    /// Amount = grouped large value + "ml", with a neutral "−" and a brand-blue "+".
    private var amountStepper: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                TextField("0", text: $amount)
                    .keyboardType(.decimalPad)
                    .font(.title3.weight(.semibold)).monospacedDigit()
                    .fixedSize()
                Text("ml").font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BBColor.nested, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(BBColor.fieldStroke, lineWidth: 0.5)
            }

            stepperButton(system: "minus", tint: false) { adjustAmount(-5) }
            stepperButton(system: "plus", tint: true) { adjustAmount(5) }
        }
    }

    private func stepperButton(system: String, tint: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system).font(.system(size: 17, weight: .medium))
                .frame(width: 38, height: 38)
                .foregroundStyle(tint ? BBColor.brandAccent : Color.secondary)
                .background(tint ? BBColor.brandTint : BBColor.controlFill,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func adjustAmount(_ delta: Double) {
        let next = max(0, (Double(amount) ?? 0) + delta)
        amount = trimmed(next)
    }

    // MARK: Tags & notes cards

    private var tagsCard: some View {
        BBCard(cornerRadius: BBRadius.tile) { TagField(selected: $tagNames) }
    }

    private var showsNotes: Bool {
        switch kind {
        case .tummyTime, .note, .timer, .child: return false
        default: return true
        }
    }

    private var notesCard: some View {
        BBCard(cornerRadius: BBRadius.tile) {
            TextField("Add a note…", text: $notes, axis: .vertical)
                .lineLimit(2...6)
                .frame(maxWidth: .infinity, minHeight: 36, alignment: .topLeading)
        }
    }

    // MARK: Action buttons

    /// Whether a "Start timer instead" action makes sense — only when creating a fresh
    /// feeding/sleep/tummy record (the kinds that map to a quick-start ``TimerActivity``).
    private var timerActivity: TimerActivity? {
        guard !isEditing, !isConverting else { return nil }
        switch kind {
        case .feeding: return .feeding
        case .sleep: return .sleep
        case .tummyTime: return .tummyTime
        default: return nil
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: save) {
                Label("Save \(kind.displayName)",
                      systemImage: isConverting ? "arrow.triangle.merge" : "checkmark")
            }
            .buttonStyle(.bbPrimary)
            .disabled(!isValid)

            if let activity = timerActivity {
                Button { startTimer(activity) } label: {
                    Label("Start timer instead", systemImage: "play.fill")
                }
                .buttonStyle(BBFilledButton(background: BBColor.brandTint, foreground: BBColor.brandAccent))
            }

            if isEditing {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete \(kind.displayName)", systemImage: "trash")
                }
                .buttonStyle(BBFilledButton(background: BBColor.danger, foreground: .white))
            }
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

    private var measurementLabel: String {
        switch kind {
        case .weight: return "Weight"
        case .height: return "Height"
        case .headCircumference: return "Head circumference"
        case .bmi: return "BMI"
        default: return "Value"
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
            // Full timer-stop coverage: feeding/pumping (and any editor-based convert) finish
            // here rather than via the dashboard's one-tap path.
            let activity = TimerActivity(convertKind: kind)?.rawValue ?? "other"
            Analytics.timerStopped(activity: activity, source: .app)
        } else if let entity {
            repo.update(entity, payload: payload)
        } else {
            repo.create(kind: kind, payload: payload)
        }
        Task { await sync.sync() }
        dismiss()
    }

    /// Begin timing this activity instead of logging a finished record. Creates an open-ended
    /// Baby Buddy timer through the same ``LocalRepository/create`` path the Start Timer sheet
    /// uses; the timer is named after the activity so the convert/widget flow recognizes it.
    private func startTimer(_ activity: TimerActivity) {
        let payload: [String: Any] = [
            "child": childID,
            "start": APIDate.isoDateTime.string(from: start),
            "name": activity.timerName,
        ]
        LocalRepository(context: context).create(kind: .timer, payload: payload)
        Analytics.timerStarted(activity: activity.rawValue, source: .app)
        Task { await sync.sync() }
        dismiss()
    }

    private func delete() {
        guard let entity else { return }
        LocalRepository(context: context).delete(entity)
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

/// Compact, presentation-only labels for the feeding-type segmented control (the model's
/// full `label` — e.g. "Fortified Breast Milk" — is too long for four segments).
private extension FeedingType {
    var shortLabel: String {
        switch self {
        case .breastMilk: return "Breast"
        case .formula: return "Formula"
        case .fortifiedBreastMilk: return "Fortified"
        case .solidFood: return "Solid"
        }
    }
}

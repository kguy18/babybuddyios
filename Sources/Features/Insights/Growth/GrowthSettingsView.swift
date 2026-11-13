import SwiftUI

struct GrowthSettingsView: View {
    @Binding var profile: GrowthProfile
    let birthDate: Date?

    var body: some View {
        Form {
            Section {
                Picker(growthText("Stored weight unit"), selection: $profile.sourceWeightUnit) {
                    ForEach(GrowthWeightUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                }
                .onChange(of: profile.sourceWeightUnit) { _, _ in profile.unitsConfirmed = false }
                Picker(growthText("Stored length unit"), selection: $profile.sourceLengthUnit) {
                    ForEach(GrowthLengthUnit.allCases, id: \.self) { Text($0.symbol).tag($0) }
                }
                .onChange(of: profile.sourceLengthUnit) { _, _ in profile.unitsConfirmed = false }
                Toggle(growthText("I have checked the stored units"), isOn: $profile.unitsConfirmed)
                    .accessibilityIdentifier("growth-units-confirmed")
                Picker(growthText("Show weight in"), selection: $profile.displayWeightUnit) {
                    Text("kg").tag(GrowthWeightUnit.kilograms)
                    Text("g").tag(GrowthWeightUnit.grams)
                }
            } header: {
                Text(growthText("Units"))
            } footer: {
                Text(growthText("Choose the units used for existing records on your server. Only the display changes; saved values stay the same."))
            }

            Section {
                Toggle(growthText("Show WHO reference curves"), isOn: $profile.showWHO)
                    .accessibilityIdentifier("growth-who-enabled")
                Picker(growthText("WHO reference"), selection: $profile.referenceSex) {
                    Text(growthText("Choose a reference")).tag(GrowthReferenceSex.none)
                    Text(growthText("Girls")).tag(GrowthReferenceSex.girls)
                    Text(growthText("Boys")).tag(GrowthReferenceSex.boys)
                }
                Toggle(growthText("Use chronological age"), isOn: $profile.chronologicalAgeConfirmed)
                    .disabled(profile.useCorrectedAge)
                Toggle(growthText("Use a documented due date for corrected age"), isOn: $profile.useCorrectedAge)
                if profile.useCorrectedAge {
                    DatePicker(growthText("Expected due date"), selection: dueDate,
                               in: (birthDate ?? .now)...Date.distantFuture, displayedComponents: .date)
                    Toggle(growthText("This due date comes from a medical record"), isOn: $profile.dueDateDocumented)
                }
                Toggle(growthText("Length measurement method confirmed"), isOn: $profile.lengthMethodConfirmed)
            } header: {
                Text(growthText("Optional WHO comparison"))
            } footer: {
                VStack(alignment: .leading, spacing: 8) {
                    Text(growthText("The API does not provide reference sex or gestational age. Choose the appropriate reference and age basis with your care team. Nothing is inferred."))
                    Text(growthText("WHO length references use recumbent length through day 730 and standing height from day 731. Enable length references only when recorded measurements follow that method."))
                    Text(growthText("Corrected age uses the documented due date instead of birth date. Curves stay hidden before that date or when required information is missing."))
                }
            }

            Section {
                Link(growthText("WHO Child Growth Standards"),
                     destination: URL(string: "https://www.who.int/tools/child-growth-standards/standards")!)
                Text(growthText("Reference curves describe a population. They do not diagnose a condition or replace an individual assessment."))
            }
        }
        .navigationTitle(growthText("Growth settings"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var dueDate: Binding<Date> {
        Binding(get: { GrowthDate.parse(profile.dueDate) ?? birthDate ?? .now },
                set: { profile.dueDate = GrowthDate.string($0) })
    }
}

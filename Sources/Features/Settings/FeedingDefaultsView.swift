import SwiftUI

struct FeedingDefaultsView: View {
    @AppStorage(FeedingDefaults.modeKey) private var mode: FeedingDefaults.Mode = .app
    @AppStorage(FeedingDefaults.typeKey) private var type: FeedingType = .breastMilk
    @AppStorage(FeedingDefaults.methodKey) private var method: FeedingMethod = .leftBreast

    var body: some View {
        Form {
            Section {
                Picker("Prefill new feedings", selection: $mode) {
                    ForEach(FeedingDefaults.Mode.allCases) { Text($0.label).tag($0) }
                }
                .accessibilityIdentifier("feeding-defaults-mode")
            } footer: {
                Text("These choices apply on this device. Quick log widget settings are separate.")
            }
            if mode != .app {
                Section {
                    Picker("Feeding type", selection: $type) {
                        ForEach(FeedingType.allCases) { Text($0.label).tag($0) }
                    }
                    .accessibilityIdentifier("feeding-defaults-type")
                    Picker("Feeding method", selection: $method) {
                        ForEach(FeedingMethod.allCases) { Text($0.label).tag($0) }
                    }
                    .accessibilityIdentifier("feeding-defaults-method")
                } footer: {
                    Text(mode == .remember
                         ? String(localized: "Saving a new feeding updates these choices. Amounts and times are not remembered.")
                         : String(localized: "New feedings start with these choices. You can change them before saving."))
                }
            }
        }
        .tint(BBColor.brandAccent)
        .navigationTitle("Feeding defaults")
        .navigationBarTitleDisplayMode(.inline)
    }
}

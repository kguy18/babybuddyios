import SwiftUI
import WidgetKit

struct ForecastSettingsView: View {
    @AppStorage(ForecastPreferences.enabledKey, store: SharedDefaults.suite) private var enabled = false

    var body: some View {
        Form {
            Section {
                Toggle(forecastText("Show activity estimates"), isOn: $enabled)
                    .accessibilityIdentifier("forecast-enabled")
            } footer: {
                Text(forecastText("Optional estimates on Home and the medium status widget. They use only the selected child's cached records, without a network request."))
            }
            Section(forecastText("How it works")) {
                Text(forecastText("Uses the last 14 days and up to ten similar intervals near the same time of day. At least four intervals across three days are required. Sparse, irregular, incomplete or stale data produces no estimate."))
                Text(forecastText("Feeding intervals run from start to start. Nap intervals run from the end of one sleep to the start of a logged nap. Wake-up estimates use previous sleep durations when a sleep timer is running."))
                Text(forecastText("Displayed windows summarize past entries. They are not a prescribed schedule, a probability, or a prediction validated for medical use."))
            }
        }
        .navigationTitle(forecastText("Activity estimates"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: enabled) { _, _ in WidgetCenter.shared.reloadAllTimelines() }
    }
}

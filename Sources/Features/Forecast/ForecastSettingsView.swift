import SwiftUI
import WidgetKit

struct ForecastSettingsView: View {
    @AppStorage(ForecastPreferences.enabledKey, store: SharedDefaults.suite) private var enabled = false
    @AppStorage(ForecastPreferences.tilesKey, store: SharedDefaults.suite) private var tiles = true
    @AppStorage(ForecastPreferences.sectionKey, store: SharedDefaults.suite) private var section = true
    @AppStorage(ForecastPreferences.widgetKey, store: SharedDefaults.suite) private var widget = true

    var body: some View {
        Form {
            Section {
                Toggle(forecastText("Show activity estimates"), isOn: $enabled)
                    .tint(BBColor.primary)
                    .accessibilityIdentifier("forecast-enabled")
                if enabled {
                    Toggle(forecastText("On the Today tiles"), isOn: $tiles)
                        .tint(BBColor.primary)
                        .accessibilityIdentifier("forecast-tiles")
                    Toggle(forecastText("What's next section"), isOn: $section)
                        .tint(BBColor.primary)
                        .accessibilityIdentifier("forecast-section")
                    Toggle(forecastText("Status widget"), isOn: $widget)
                        .tint(BBColor.primary)
                        .accessibilityIdentifier("forecast-widget")
                }
            } footer: {
                Text(enabled
                     ? forecastText("Tiles show one time each. What's next opens from Home with the full windows and how each was worked out.")
                     : forecastText("Optional estimates on Home and the medium status widget. They use only the selected child's cached records, without a network request."))
            }
            Section {
                Text(forecastText("Uses the last 14 days and up to ten similar intervals near the same time of day. At least four intervals across three days are required. Sparse, irregular, incomplete, or stale data produces no estimate."))
                Text(forecastText("Feeding intervals run from start to start. Nap intervals run from the end of one sleep to the start of a logged nap. Wake-up estimates use previous sleep durations when a sleep timer is running."))
                Text(forecastText("Displayed windows summarize past entries. They are not a prescribed schedule, a probability, or a prediction validated for medical use."))
            } header: {
                Text(forecastText("How it works"))
            } footer: {
                Text(forecastText("Based on logged routines, not your baby's current needs. Follow your baby's cues and your care plan; do not wait for an estimate to feed or check a diaper."))
            }
        }
        .navigationTitle(forecastText("Activity estimates"))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: enabled) { _, newValue in
            Analytics.settingChanged("activityEstimates", enabled: newValue)
            WidgetCenter.shared.reloadAllTimelines()
        }
        .onChange(of: tiles) { _, newValue in Analytics.settingChanged("activityEstimatesTiles", enabled: newValue) }
        .onChange(of: section) { _, newValue in Analytics.settingChanged("activityEstimatesSection", enabled: newValue) }
        .onChange(of: widget) { _, newValue in
            Analytics.settingChanged("activityEstimatesWidget", enabled: newValue)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}

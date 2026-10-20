import SwiftUI
import OpenWish

/// Settings ▸ Request a Feature: the OpenWish board at feedback.babybuddy.app.
///
/// The SDK is configured on first open, not at launch, so a user who never opens the board never
/// talks to the server. It identifies the device by a random UUID it keeps in standard defaults.
/// Nothing else about the user is sent: no `updateUser`, and no email field on a new request.
enum FeatureRequests {
    /// `OPENWISH_API_KEY` in Config/Secrets.xcconfig, through the `OpenWishAPIKey` Info.plist key.
    private static let apiKey = Bundle.main.object(forInfoDictionaryKey: "OpenWishAPIKey") as? String ?? ""

    /// Hidden without a key, and under `BB_UITEST` whatever the key, so a local Secrets.xcconfig
    /// can't change what the UI tests see. `BB_FEEDBACK=1` shows the row anyway.
    static var isAvailable: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["BB_FEEDBACK"] == "1" { return true }
        return !apiKey.isEmpty && environment["BB_UITEST"] != "1"
    }

    @MainActor private static var isConfigured = false

    @MainActor static func configure() {
        guard !isConfigured else { return }
        isConfigured = true
        OpenWish.configure(with: apiKey, apiUrl: "https://feedback.babybuddy.app/api")

        // The SDK's Theme takes three colors; everything else it draws in system colors.
        OpenWish.theme.primaryColor = BBColor.primary
        OpenWish.theme.secondaryColor = .setBoth(to: BBColor.card)
        OpenWish.theme.tertiaryColor = .setBoth(to: BBColor.surface)
        OpenWish.config.buttons.addButton.textColor = .setBoth(to: .white)
        OpenWish.config.cornerRadius = BBRadius.tile
        OpenWish.config.emailField = .none
    }
}

/// The SDK's list, in a sheet: its own close button dismisses the presentation it's in.
struct FeatureRequestsSheet: View {
    init() { FeatureRequests.configure() }

    var body: some View {
        NavigationStack { OpenWish.FeedbackListView() }
    }
}

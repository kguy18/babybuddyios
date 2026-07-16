import WidgetKit
import SwiftUI

/// Shown in place of a Home Screen widget's content when the customer isn't premium — Home Screen
/// widgets are a Baby Buddy Premium feature. Tapping opens the app's paywall (`babybuddy://premium`).
struct WidgetLockedView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "crown.fill")
                .font(.system(size: 22))
                .foregroundStyle(BBColor.stop)
            Text("Baby Buddy Premium")
                .font(.system(size: 13, weight: .semibold))
                .multilineTextAlignment(.center)
            Text("Tap to unlock widgets")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(URL(string: "babybuddy://premium"))
    }
}

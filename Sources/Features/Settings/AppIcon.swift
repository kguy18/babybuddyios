import Foundation
import Observation
import UIKit

/// One of the six home-screen icons that ship with the app — the same mascot peeking over the
/// Baby Buddy cloud, in six poses.
///
/// Every icon is free. Nothing here consults ``PurchaseManager``: the app's whole position is that
/// features cost nothing and tipping is optional, and a locked icon grid would be the first place
/// that stopped being true.
///
/// The raw value is the stable name used for analytics; ``alternateIconName`` is the asset-catalog
/// name UIKit resolves against and must match `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in
/// `project.yml`. A name in one list and not the other fails at runtime, not at build time.
enum AppIconOption: String, CaseIterable, Identifiable, Sendable {
    /// The primary icon — the mascot centered, peeking over the cloud. The app's default.
    case centerPeek
    case happyLowPeek
    case lowPeek
    case peekWave
    case sidePeekLeft
    case sidePeekRight

    var id: String { rawValue }

    /// The name `UIApplication.setAlternateIconName(_:)` expects, or `nil` for the primary icon —
    /// which is what that API takes to mean "put the original back".
    var alternateIconName: String? {
        switch self {
        case .centerPeek: return nil
        case .happyLowPeek: return "AppIconHappyLowPeek"
        case .lowPeek: return "AppIconLowPeek"
        case .peekWave: return "AppIconPeekWave"
        case .sidePeekLeft: return "AppIconSidePeekLeft"
        case .sidePeekRight: return "AppIconSidePeekRight"
        }
    }

    /// The imageset holding this icon's preview, drawn by the picker grid.
    ///
    /// A separate, downscaled copy of the artwork rather than the `.appiconset` itself: `actool`
    /// compiles app icons as `Icon Image` renditions, which `UIImage(named:)` cannot resolve at all
    /// — asking it for `"AppIcon"` returns `nil` even though the artwork is right there in the
    /// catalog. These are 240px, which covers the 74pt tile at @3x, so the 1024px originals ship
    /// once as icons instead of twice.
    var previewAssetName: String { "appicon_\(rawValue)" }

    /// How the option reads under its preview.
    var displayName: String {
        switch self {
        case .centerPeek: return "Center Peek"
        case .happyLowPeek: return "Happy Low Peek"
        case .lowPeek: return "Low Peek"
        case .peekWave: return "Peek Wave"
        case .sidePeekLeft: return "Side Peek Left"
        case .sidePeekRight: return "Side Peek Right"
        }
    }

    /// The option matching what UIKit reports as the current icon, defaulting to the primary.
    ///
    /// Pure, and the inverse of ``alternateIconName``, so the round trip the whole screen depends on
    /// is unit-testable — the `UIApplication` side of this feature is not.
    static func matching(alternateIconName name: String?) -> AppIconOption {
        guard let name else { return .centerPeek }
        return allCases.first { $0.alternateIconName == name } ?? .centerPeek
    }
}

/// The home-screen icon the customer has chosen, and the one way to change it.
///
/// Holds no preference of its own: `UIApplication.alternateIconName` **is** the stored value — iOS
/// persists the choice across launches, updates, and even a restore from backup — so ``selected``
/// is a mirror of it rather than a second copy in `UserDefaults` that could drift out of step with
/// the icon actually on the home screen.
///
/// Views observe this object (it is `@Observable`, so any `private(set)` property drives SwiftUI
/// updates) and call the async ``select(_:)``; failures land in ``errorMessage`` rather than being
/// thrown at the UI, matching ``PurchaseManager``.
@MainActor
@Observable
final class AppIconManager {
    /// The icon currently on the home screen.
    private(set) var selected: AppIconOption

    /// User-presentable message for the last failed change, or `nil` if the last one succeeded.
    private(set) var errorMessage: String?

    /// Whether the platform allows alternate icons at all. Always `true` on iPhone and iPad today,
    /// but it is the documented precondition for `setAlternateIconName`, so the picker asks rather
    /// than assumes and hides itself if the answer is ever `false`.
    var isSupported: Bool { UIApplication.shared.supportsAlternateIcons }

    init() {
        selected = .matching(alternateIconName: UIApplication.shared.alternateIconName)
    }

    /// Switches the home-screen icon, showing iOS's own "You have changed the icon" confirmation.
    ///
    /// A no-op when the requested icon is already set — `setAlternateIconName` treats that as an
    /// error, and it would put an alert (and a failure message) in front of someone who just tapped
    /// the icon they already have.
    func select(_ option: AppIconOption) async {
        // Ask UIKit rather than trusting `selected`: it is the source of truth, and this keeps a
        // tap on the current icon silent even if the two ever drift.
        guard option.alternateIconName != UIApplication.shared.alternateIconName else {
            selected = option
            errorMessage = nil
            return
        }
        do {
            try await UIApplication.shared.setAlternateIconName(option.alternateIconName)
            selected = option
            errorMessage = nil
            Analytics.appIconChanged(option.rawValue)
        } catch {
            // Snap the selection back to whatever the system actually has, so a failed change can
            // never leave the grid showing a checkmark on an icon that isn't on the home screen.
            selected = .matching(alternateIconName: UIApplication.shared.alternateIconName)
            errorMessage = "Couldn't change the app icon. Please try again."
        }
    }
}

import XCTest
import UIKit
@testable import BabyBuddy

/// Covers the part of the app-icon feature that *can* be tested without changing the Home Screen:
/// the mapping between ``AppIconOption`` and the names UIKit deals in.
///
/// ``AppIconManager/select(_:)`` itself calls `UIApplication.setAlternateIconName`, which needs a
/// real app process and puts a system alert on screen, so the switch is verified by hand in the
/// simulator rather than here.
final class AppIconTests: XCTestCase {

    /// The primary icon is the one `setAlternateIconName(nil)` restores; every other option must
    /// carry a name. A `nil` slipping into an alternate would silently reset the icon instead of
    /// changing it.
    func testOnlyPrimaryHasNoAlternateName() {
        XCTAssertNil(AppIconOption.centerPeek.alternateIconName)
        for option in AppIconOption.allCases where option != .centerPeek {
            XCTAssertNotNil(option.alternateIconName, "\(option.rawValue) needs an alternate name")
        }
    }

    /// Names must be distinct — a duplicate would make ``AppIconOption/matching(alternateIconName:)``
    /// resolve two designs to whichever comes first in `allCases`.
    func testAlternateNamesAreUnique() {
        let names = AppIconOption.allCases.compactMap(\.alternateIconName)
        XCTAssertEqual(names.count, Set(names).count)
        XCTAssertEqual(names.count, AppIconOption.allCases.count - 1)
    }

    /// The round trip the picker's selection state depends on.
    func testMatchingRecoversEveryOption() {
        for option in AppIconOption.allCases {
            XCTAssertEqual(AppIconOption.matching(alternateIconName: option.alternateIconName), option)
        }
    }

    /// No icon set (`nil`) and an icon we don't ship both fall back to the primary, rather than
    /// leaving the grid with nothing selected.
    func testMatchingFallsBackToPrimary() {
        XCTAssertEqual(AppIconOption.matching(alternateIconName: nil), .centerPeek)
        XCTAssertEqual(AppIconOption.matching(alternateIconName: "AppIconRetired"), .centerPeek)
    }

    /// Every option's preview resolves. Guards the half of the feature the compiler can't see: a
    /// new icon added to ``AppIconOption`` without its `appicon_<rawValue>` imageset still builds
    /// and just leaves a placeholder in the grid.
    func testEveryOptionHasAPreview() {
        for option in AppIconOption.allCases {
            XCTAssertNotNil(UIImage(named: option.previewAssetName),
                            "no preview for \(option.previewAssetName) — is it in Assets.xcassets?")
        }
    }

    /// The previews are downscaled copies, not the 1024px originals. A full-size PNG slipping in
    /// here would quietly add megabytes to the app for artwork drawn at 74pt.
    func testPreviewsAreDownscaled() throws {
        for option in AppIconOption.allCases {
            let image = try XCTUnwrap(UIImage(named: option.previewAssetName))
            XCTAssertLessThanOrEqual(image.size.width * image.scale, 240,
                                     "\(option.previewAssetName) is larger than the tile needs")
        }
    }

    /// Each alternate must also be declared in the build settings, or `setAlternateIconName` throws
    /// at runtime for a name that looks perfectly valid in Swift. Xcode turns that list into
    /// `CFBundleAlternateIcons`, so the built Info.plist is where the two can be compared.
    func testEveryAlternateIsDeclaredInTheBundle() throws {
        let icons = try XCTUnwrap(Bundle.main.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any])
        let alternates = try XCTUnwrap(icons["CFBundleAlternateIcons"] as? [String: Any])
        for option in AppIconOption.allCases {
            guard let name = option.alternateIconName else { continue }
            XCTAssertNotNil(alternates[name],
                            "\(name) is missing from ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES")
        }
        XCTAssertEqual(alternates.count, AppIconOption.allCases.count - 1,
                       "the build declares alternates that AppIconOption doesn't offer")
    }

    /// The manager mirrors UIKit at init rather than keeping its own copy.
    @MainActor
    func testManagerStartsFromTheSystemIcon() {
        let manager = AppIconManager()
        XCTAssertEqual(manager.selected,
                       .matching(alternateIconName: UIApplication.shared.alternateIconName))
        XCTAssertNil(manager.errorMessage)
    }
}

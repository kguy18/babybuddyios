import XCTest
@testable import BabyBuddy

final class GrowthLocalizationTests: XCTestCase {
    func testFeatureCatalogHasGermanAndEnglishFallback() throws {
        let germanPath = try XCTUnwrap(Bundle.main.path(forResource: "de", ofType: "lproj"))
        let german = try XCTUnwrap(Bundle(path: germanPath))
        XCTAssertEqual(german.localizedString(forKey: "Growth settings", value: nil, table: "Growth"), "Wachstumseinstellungen")
        XCTAssertEqual(german.localizedString(forKey: "Head circumference", value: nil, table: "Growth"), "Kopfumfang")
        let englishPath = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try XCTUnwrap(Bundle(path: englishPath))
        XCTAssertEqual(english.localizedString(forKey: "Growth settings", value: nil, table: "Growth"), "Growth settings")
    }
}

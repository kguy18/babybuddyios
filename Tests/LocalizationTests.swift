import XCTest
@testable import BabyBuddy

final class LocalizationTests: XCTestCase {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testGermanResourcesAreBundledAndSelectedBySystemPreferences() throws {
        XCTAssertTrue(Bundle.main.localizations.contains("de-DE"))
        XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations,
                                                     forPreferences: ["de-DE", "en"]).first, "de-DE")
        XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations,
                                                     forPreferences: ["de"]).first, "de-DE")
        let german = try bundle("de-DE")
        XCTAssertEqual(String(localized: "Settings", bundle: german), "Einstellungen")
        XCTAssertEqual(String(localized: "Bottle", bundle: german), "Flasche")
        XCTAssertEqual(String(localized: "feeding.type.solid.short", defaultValue: "Solid", bundle: german),
                       "Beikost")
        XCTAssertEqual(String(localized: "Wet + Solid", bundle: german), "Nass + Stuhlgang")
        XCTAssertEqual(String(localized: "Active timer", bundle: german), "Aktiver Timer")
    }

    func testGermanAndEnglishPluralForms() throws {
        let german = try bundle("de-DE")
        let english = try bundle("en")
        for (count, de, en) in [(0, "0 Felder", "0 fields"), (1, "1 Feld", "1 field"),
                               (2, "2 Felder", "2 fields")] {
            XCTAssertEqual(String(localized: "\(count) fields", bundle: german,
                                  locale: Locale(identifier: "de_DE")), de)
            XCTAssertEqual(String(localized: "\(count) fields", bundle: english,
                                  locale: Locale(identifier: "en_US")), en)
        }
    }

    func testGermanPlaceholdersCanChangeOrder() throws {
        let german = try bundle("de-DE")
        let duration = "4 Std.", childName = "Ada", time = "12:30"
        XCTAssertEqual(String(localized: "\(duration) since \(childName)'s last dose at \(time).",
                              bundle: german, locale: Locale(identifier: "de_DE")),
                       "Ada: Seit der letzten Gabe um 12:30 sind 4 Std. vergangen.")
    }

    func testEnglishFallbackAndMissingTranslations() throws {
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        XCTAssertEqual(String(localized: "Settings", bundle: try bundle("en")), "Settings")
        XCTAssertEqual(String(localized: "Untranslated test message", bundle: try bundle("de-DE")),
                       "Untranslated test message")
    }

    func testPermissionPromptsAreLocalized() throws {
        let german = try bundle("de-DE")
        let message = german.localizedString(forKey: "NSCameraUsageDescription", value: nil, table: "InfoPlist")
        XCTAssertTrue(message.contains("Anmelde-QR-Code"))
    }

    func testDisplayTranslationDoesNotChangePayloadValuesOrTimerIdentity() {
        XCTAssertEqual(FeedingType.breastMilk.rawValue, "breast milk")
        XCTAssertEqual(FeedingMethod.leftBreast.rawValue, "left breast")
        XCTAssertEqual(DiaperColor.brown.rawValue, "brown")
        XCTAssertEqual(TimerActivity.tummyTime.timerName, "Tummy time")
        XCTAssertEqual(TimerActivity(timerName: "Tummy time"), .tummyTime)
        XCTAssertEqual(EntityFormatting.timerName("My custom timer"), "My custom timer")
    }
}

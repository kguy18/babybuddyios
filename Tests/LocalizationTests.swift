import XCTest
@testable import BabyBuddy

final class LocalizationTests: XCTestCase {
    private func bundle(_ language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"))
        return try XCTUnwrap(Bundle(path: path))
    }

    func testGermanResourcesAreBundledAndSelectedBySystemPreferences() throws {
        XCTAssertTrue(Bundle.main.localizations.contains("de"))
        XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations,
                                                     forPreferences: ["de-DE", "en"]).first, "de")
        XCTAssertEqual(Bundle.preferredLocalizations(from: Bundle.main.localizations,
                                                     forPreferences: ["de-AT"]).first, "de")
        let german = try bundle("de")
        XCTAssertEqual(String(localized: "Settings", bundle: german), "Einstellungen")
        XCTAssertEqual(String(localized: "Bottle", bundle: german), "Flasche")
        XCTAssertEqual(String(localized: "feeding.type.solid.short", defaultValue: "Solid", bundle: german),
                       "Beikost")
        XCTAssertEqual(String(localized: "Wet + Solid", bundle: german), "Nass + Stuhlgang")
        XCTAssertEqual(String(localized: "Active timer", bundle: german), "Aktiver Timer")
    }

    func testGermanAndEnglishPluralForms() throws {
        let german = try bundle("de")
        let english = try bundle("en")
        for (count, de, en) in [(0, "0 Felder", "0 fields"), (1, "1 Feld", "1 field"),
                               (2, "2 Felder", "2 fields")] {
            XCTAssertEqual(String(localized: "\(count) fields", bundle: german,
                                  locale: Locale(identifier: "de_DE")), de)
            XCTAssertEqual(String(localized: "\(count) fields", bundle: english,
                                  locale: Locale(identifier: "en_US")), en)
        }
    }

    func testDayTimelinePaneEmptyStateUsesTheSelectedLanguage() throws {
        let german = try bundle("de")
        let english = try bundle("en")
        for (key, translation) in [
            ("Nothing logged today", "Heute noch keine Einträge"),
            ("What you log today shows here.", "Hier erscheinen deine heutigen Einträge.")
        ] {
            XCTAssertEqual(german.localizedString(forKey: key, value: nil, table: nil), translation)
            XCTAssertEqual(english.localizedString(forKey: key, value: nil, table: nil), key)
        }
    }

    func testGermanPlaceholdersCanChangeOrder() throws {
        let german = try bundle("de")
        let duration = "4 Std.", childName = "Ada", time = "12:30"
        XCTAssertEqual(String(localized: "\(duration) since \(childName)'s last dose at \(time).",
                              bundle: german, locale: Locale(identifier: "de_DE")),
                       "Ada: Seit der letzten Gabe um 12:30 sind 4 Std. vergangen.")
    }

    func testSickModeFragmentsAndTrendAreGerman() throws {
        let german = try bundle("de")
        for (key, translated) in [("yesterday", "gestern"), ("up", "gestiegen"),
                                  ("down", "gesunken"), ("this phone only", "nur auf diesem Gerät"),
                                  ("from your server", "von deinem Server")] {
            XCTAssertEqual(german.localizedString(forKey: key, value: nil, table: nil), translated)
        }
        let when = "gestern 13:50", delta = "0,5"
        for direction in ["gestiegen", "gesunken"] {
            XCTAssertEqual(String(localized: "\(direction) \(delta)° since \(when)", bundle: german),
                           "seit gestern 13:50 um 0,5° \(direction)")
        }
    }

    func testEnglishFallbackAndMissingTranslations() throws {
        XCTAssertEqual(Bundle.main.developmentLocalization, "en")
        XCTAssertEqual(String(localized: "Settings", bundle: try bundle("en")), "Settings")
        XCTAssertEqual(String(localized: "Untranslated test message", bundle: try bundle("de")),
                       "Untranslated test message")
    }

    func testPermissionPromptsAreLocalized() throws {
        let german = try bundle("de")
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

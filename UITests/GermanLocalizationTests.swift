import XCTest

final class GermanLocalizationTests: UITestCase {
    func testGermanOnboarding() {
        launch(demo: false, language: "de-DE", locale: "de_DE")
        expect(app.staticTexts["Mit deinem eigenen Server verbinden"])
        expect(app.buttons["QR-Code scannen"])
        expect(app.textFields["URL oder IP-Adresse deines Servers"])
        expect(app.secureTextFields["API-Token einfügen"])
    }

    func testGermanEditorAndNavigation() {
        launch(["BB_OPEN": "feeding"], language: "de-DE", locale: "de_DE")
        expect(app.navigationBars["Mahlzeit hinzufügen"])
        expect(app.staticTexts["Methode"])
        expect(app.buttons["Speichern"])
        tap(app.buttons["Abbrechen"])
        for title in ["Verlauf", "Statistiken", "Einstellungen", "Übersicht"] {
            tap(app.tabBars.buttons[title])
        }
        expect(app.buttons.labeled("Timer starten"))
    }

    func testGermanDayTimelineCanStillOpenItsActivityEditor() {
        launch(language: "de-DE", locale: "de_DE")
        tap(app.descendants(matching: .any)["today-feeding"])
        expect(app.navigationBars["Mahlzeit · Heute"])
        tap(app.buttons.labeled("Mahlzeit hinzufügen"))
        expect(app.navigationBars["Mahlzeit hinzufügen"])
        expect(app.buttons["Speichern"])
        tap(app.buttons["Abbrechen"])
        expect(app.navigationBars["Mahlzeit · Heute"])
    }
}

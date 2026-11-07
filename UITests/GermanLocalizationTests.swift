import XCTest

final class GermanLocalizationTests: UITestCase {
    func testGermanLatestIdentifiesSessionEnds() {
        launch(language: "de", locale: "de_DE")
        expect(elements("label BEGINSWITH 'Schlaf, ' AND label CONTAINS 'aufgewacht'").firstMatch)
        expect(elements("label BEGINSWITH 'Mahlzeit, ' AND label CONTAINS 'beendet'").firstMatch)
    }

    func testGermanOnboarding() {
        launch(demo: false, language: "de", locale: "de_DE")
        expect(app.staticTexts["Mit deinem eigenen Server verbinden"])
        expect(app.buttons.labeled("QR-Code scannen"))
        expect(app.textFields["URL oder IP-Adresse deines Servers"])
        expect(app.secureTextFields["API-Token einfügen"])
    }

    func testGermanEditorAndNavigation() {
        launch(["BB_OPEN": "feeding"], language: "de", locale: "de_DE")
        let editor = expect(app.navigationBars["Mahlzeit hinzufügen"])
        expect(app.staticTexts["Methode"])
        expect(editor.buttons["Speichern"])
        tap(editor.buttons["Abbrechen"])
        tap(app.buttons["Hinzufügen"])
        expect(app.buttons["Timer starten"])
        tap(app.buttons["Schließen"])
        // Coming back to Home would reopen the BB_OPEN editor, so the test ends on another tab.
        for title in ["Verlauf", "Statistiken", "Einstellungen"] {
            tap(tab(title))
        }
        expect(tab("Übersicht"))
    }

    func testGermanDayTimelineCanStillOpenItsActivityEditor() {
        launch(language: "de", locale: "de_DE")
        tap(app.descendants(matching: .any)["today-feeding"])
        expect(app.navigationBars["Mahlzeit · Heute"])
        tap(app.buttons.labeled("Mahlzeit hinzufügen"))
        let editor = expect(app.navigationBars["Mahlzeit hinzufügen"])
        expect(editor.buttons["Speichern"])
        tap(editor.buttons["Abbrechen"])
        expect(app.navigationBars["Mahlzeit · Heute"])
    }
}

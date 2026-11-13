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

    func testGermanMedicationUnitMenuAndSavedDose() {
        launch(language: "de", locale: "de_DE")
        openGermanMedicationEditor()

        let title = "Medikament hinzufügen"
        let editor = expect(app.navigationBars[title])
        let unitMenu = expect(app.buttons["Dosiseinheit"])
        XCTAssertFalse(app.buttons["Eigene Einheit hinzufügen"].exists)
        expectValue(unitMenu, "Ohne Einheit")
        tap(unitMenu)
        for unit in ["Ohne Einheit", "mg", "mL", "Tabletten", "Tropfen"] {
            expect(app.buttons[unit])
        }
        tap(app.buttons["Tropfen"])
        expectValue(unitMenu, "Tropfen")

        let name = app.textFields["Name"]
        tap(name)
        name.typeText("Testmed")
        let amount = app.textFields["0"]
        tap(amount)
        amount.typeText("2")
        revealSheetBar(title)
        tap(editor.buttons["Speichern"])
        expectGone(editor)

        tap(tab("Verlauf"))
        let row = expect(elements("label BEGINSWITH 'Medikament, Testmed' AND label CONTAINS '2 Tropfen'").firstMatch)
        tap(row)
        expect(app.navigationBars["Medikament bearbeiten"])
        expectValue(app.buttons["Dosiseinheit"], "Tropfen")
    }

    func testGermanCustomMedicationUnitPersistsInTheMenu() {
        launch(["BB_CUSTOM_MEDICATION_UNITS": "1"], language: "de", locale: "de_DE")
        openGermanMedicationEditor()
        let title = "Medikament hinzufügen"
        let editor = expect(app.navigationBars[title])
        tap(app.buttons["Eigene Einheit hinzufügen"])
        let alert = expect(app.alerts["Eigene Einheit hinzufügen"])
        let field = alert.textFields["Einheit"]
        tap(field)
        field.typeText("IE")
        tap(alert.buttons["Hinzufügen"])
        expectGone(alert)
        expectValue(app.buttons["Dosiseinheit"], "IE")

        revealSheetBar(title)
        tap(editor.buttons["Abbrechen"])
        expectGone(editor)
        openGermanMedicationEditor()
        tap(app.buttons["Dosiseinheit"])
        tap(app.buttons["IE"])
        expectValue(app.buttons["Dosiseinheit"], "IE")
    }

    private func openGermanMedicationEditor() {
        tap(app.buttons["Hinzufügen"])
        tap(app.buttons.labeled("Mehr …"))
        expect(app.navigationBars["Aktivität hinzufügen"])
        let medication = app.buttons["Medikament"]
        if !medication.waitForExistence(timeout: 2) { app.buttons["Mahlzeit"].swipeUp() }
        tap(medication)
    }
}

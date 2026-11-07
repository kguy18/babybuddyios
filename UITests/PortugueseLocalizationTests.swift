import XCTest

final class PortugueseLocalizationTests: UITestCase {
    func testPortugueseOnboarding() {
        launch(demo: false, language: "pt-BR", locale: "pt_BR")
        expect(app.staticTexts["Conecte ao seu servidor próprio"])
        expect(app.buttons.labeled("Escanear QR code"))
        expect(app.textFields["URL ou endereço IP do seu servidor"])
        expect(app.secureTextFields["Cole seu token de API"])
    }

    func testPortugueseEditorAndNavigation() {
        launch(["BB_OPEN": "feeding"], language: "pt-BR", locale: "pt_BR")
        let editor = expect(app.navigationBars["Adicionar Alimentação"])
        expect(app.staticTexts["Método"])
        expect(editor.buttons["Salvar"])
        tap(editor.buttons["Cancelar"])
        tap(app.buttons["Adicionar"])
        expect(app.buttons["Iniciar cronômetro"])
        tap(app.buttons["Fechar"])
        // Coming back to Home would reopen the BB_OPEN editor, so the test ends on another tab.
        for title in ["Linha do tempo", "Tendências", "Ajustes"] {
            tap(tab(title))
        }
        expect(tab("Início"))
    }
}

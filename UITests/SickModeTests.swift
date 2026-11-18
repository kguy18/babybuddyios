import XCTest

/// Sick mode: the three ways in (the fever banner, "+" ▸ More…, Settings), the Home it draws, ending
/// it with Undo, medicine colors, and a phone in °C. `BB_SEED_SICK=1` seeds a feverish child with
/// sick mode on; starting it over a fever asks for notification permission, for the temperature check.
final class SickModeTests: UITestCase {
    private var homeTab: XCUIElement { tab("Home") }

    /// Home ▸ "+" ▸ More… ▸ Temperature, `value` typed and saved.
    private func logTemperature(_ value: String) {
        openEditor("Temperature")
        let bar = expect(app.navigationBars["New Temperature"])
        let field = app.textFields["0"]
        field.tap()
        field.typeText(value)
        tap(bar.buttons["Save"])
        expectGone(bar)
    }

    /// What Home shows in sick mode, whatever has been logged, and the red dot on its tab.
    private func expectSickHome(file: StaticString = #filePath, line: UInt = #line) {
        expect(app.staticTexts["MEDICINE"], file: file, line: line)
        expect(app.buttons["End sick mode"], file: file, line: line)
        expectBadge(true, file: file, line: line)
    }

    private func expectUsualHome(file: StaticString = #filePath, line: UInt = #line) {
        expect(app.staticTexts["LATEST"], file: file, line: line)
        XCTAssertFalse(app.staticTexts["MEDICINE"].exists, "Still in sick mode", file: file, line: line)
        expectBadge(false, file: file, line: line)
    }

    /// A badge with no text has no accessibility value, and the tab reads "Home" either way. So this
    /// looks for the dot's red among the tab's pixels, a solid patch of it, which the glass never
    /// makes of a red tile scrolled underneath.
    private func expectBadge(_ shown: Bool, file: StaticString, line: UInt) {
        let tab = homeTab
        expect(tab, matching: NSPredicate { _, _ in Self.hasRed(tab.screenshot().image) == shown }, timeout: 5,
               describedAs: shown ? "to wear sick mode's red dot" : "to have lost its red dot", file: file, line: line)
    }

    private static func hasRed(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        let width = cgImage.width, height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                      bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        let red = stride(from: 0, to: pixels.count, by: 4).filter {
            pixels[$0] > 200 && pixels[$0 + 1] < 90 && pixels[$0 + 2] < 90
        }
        return red.count >= 50
    }

    func testFeverBannerStartsSickMode() {
        launch()
        expectUsualHome()
        logTemperature("102.4")
        let banner = expect(element(labeled: "102.4°F is over the fever line"))
        tap(app.buttons["Not now"])
        expectGone(banner)

        // Dismissed for that reading only: the next one over the line brings it back.
        logTemperature("102.6")
        expect(element(labeled: "102.6°F is over the fever line"))
        tap(app.buttons["Start sick mode"])
        allowNotificationsIfAsked()
        expectSickHome()
        expect(element(labeled: "Sick mode · day 1"))
    }

    func testStartByHandFromAddSheetAndSettings() {
        launch()
        tap(app.buttons["Add"])
        tap(app.buttons.labeled("More…"))
        expect(app.navigationBars["Add Activity"])
        // The row sits under the Measure grid, below the sheet's first height.
        expect(app.staticTexts["MEASURE"]).swipeUp()
        tap(app.buttons.labeled("Start sick mode"))
        expectSickHome()

        // While it's on, the sheet doesn't offer it.
        tap(app.buttons["Add"])
        tap(app.buttons.labeled("More…"))
        expect(app.navigationBars["Add Activity"])
        XCTAssertFalse(app.buttons.labeled("Start sick mode").exists)
        tap(app.navigationBars["Add Activity"].buttons["Cancel"])

        // Settings ▸ Sick mode ends it, and starts it again.
        tap(tab("Settings"))
        tap(app.buttons["End sick mode"])
        tap(app.buttons["Start sick mode"])
        expect(app.buttons["End sick mode"])
        tap(homeTab)
        expectSickHome()
    }

    func testSeededMedicineCards() {
        launch(["BB_SEED_SICK": "1"])
        allowNotificationsIfAsked()
        expectSickHome()
        // Ibuprofen's next dose is OK now; acetaminophen's is counting down.
        expect(elements("label BEGINSWITH 'Ibuprofen' AND label CONTAINS 'OK now'").firstMatch)
        expect(elements("label BEGINSWITH 'Acetaminophen' AND label CONTAINS 'until '").firstMatch)

        // Logging the OK dose opens the editor filled in from the last one.
        tap(app.buttons["Log ibuprofen · 5 mL"])
        expect(app.navigationBars["New Medication"])
        XCTAssertTrue(app.textFields.withValue("Ibuprofen").exists, "The name wasn't filled in")
    }

    /// At the largest text size "Log temperature" stays on one line, where it hyphenated.
    func testSickHomeFitsTheLargestText() {
        launch(["BB_SEED_SICK": "1"], largestText: true)
        allowNotificationsIfAsked()
        expectSickHome()
        XCTAssertLessThan(expect(app.buttons["Log temperature"]).frame.height, 120,
                          "Log temperature should fit on one line")
    }

    func testEndSickModeAndUndo() {
        launch(["BB_SEED_SICK": "1", "BB_TOAST_SECONDS": "30"])
        allowNotificationsIfAsked()
        expectSickHome()

        tap(app.buttons["End sick mode"])
        let toast = expect(app.otherElements["Sick mode ended"])
        expectUsualHome()
        XCTAssertFalse(element(labeled: "100.8°F is over the fever line").exists,
                       "Ending counts the fever on record as seen")

        tap(app.buttons["Undo"])
        expectGone(toast)
        expectSickHome()
    }

    func testSickModeChoicesAtLargestText() {
        launch(["BB_START_TAB": "settings", "BB_TEMP_UNIT": "f"], largestText: true)
        tap(app.buttons.labeled("Fever line"))
        expect(app.navigationBars["Fever line"])
        let fever = expect(app.buttons["99.5°F"])
        attachSickSettingsScreen("settings-fever-line")
        let feverHeight = fever.frame.height
        tap(fever)
        XCTAssertTrue(fever.isSelected)
        back(from: "Fever line")

        tap(app.buttons.labeled("Temperature checks"))
        expect(app.navigationBars["Temperature checks"])
        let off = expect(app.buttons["Off"])
        attachSickSettingsScreen("settings-temperature-checks")
        XCTAssertGreaterThan(feverHeight, 55)
        XCTAssertGreaterThan(off.frame.height, 55)
        tap(off)
        XCTAssertTrue(off.isSelected)
    }

    func testMedicineColorsWithoutMedicinesAtLargestText() {
        launch(["BB_START_TAB": "settings"], largestText: true)
        tap(app.buttons["Medicine colors"])
        expect(app.navigationBars["Medicine colors"])
        let next = expect(element(labeled: "Next new medicine"))
        attachSickSettingsScreen("settings-medicine-colors")
        XCTAssertTrue(next.label.contains("Red"))
        expect(app.buttons["Reset to server colors"])
    }

    func testChangingAColorWarnsFirst() {
        checkChangingAColor(largestText: false)
    }

    func testChangingAColorWarnsFirstAtLargestText() {
        checkChangingAColor(largestText: true)
    }

    private func checkChangingAColor(largestText: Bool) {
        launch(["BB_SEED_SICK": "1", "BB_START_TAB": "settings"], largestText: largestText)
        allowNotificationsIfAsked()
        tap(app.buttons["Medicine colors"])
        expect(app.navigationBars["Medicine colors"])
        let ibuprofen = app.buttons.labeled("Ibuprofen")
        expect(ibuprofen)
        XCTAssertTrue(ibuprofen.label.contains("Purple · from your server"), ibuprofen.label)
        if largestText { attachSickSettingsScreen("settings-medicine-colors-sick") }

        tap(ibuprofen)
        let pink = expect(app.buttons["Pink"])
        if largestText {
            reveal(pink, in: app.scrollViews.firstMatch)
            attachSickSettingsScreen("settings-medicine-color-picker")
        }
        tap(pink)
        expect(app.staticTexts["Only on this phone"])
        let cancel = expect(app.buttons["Cancel"])
        let use = expect(app.buttons["Use pink"])
        if largestText {
            attachSickSettingsScreen("alert-medicine-color-change")
            let change = expect(element(labeled: "Ibuprofen: Purple to Pink"))
            XCTAssertTrue(change.isHittable)
            let explanation = app.staticTexts.labeled("Your server gave ibuprofen purple")
            reveal(explanation, in: app.alerts["Color changes only on this phone"].scrollViews.firstMatch)
            XCTAssertGreaterThan(use.frame.minY, cancel.frame.maxY)
            XCTAssertTrue(use.isHittable)
        }
        tap(cancel)
        expectGone(app.staticTexts["Only on this phone"])
        XCTAssertTrue(app.buttons.labeled("Ibuprofen").label.contains("Purple · from your server"))
        XCTAssertTrue(app.buttons["Purple"].isSelected, "Cancel changed the color")

        if largestText {
            tap(pink)
            tap(use)
            expectGone(app.staticTexts["Only on this phone"])
            XCTAssertTrue(app.buttons.labeled("Ibuprofen").label.contains("Pink · this phone only"))
            XCTAssertTrue(pink.isSelected)
        }
    }

    func testCelsiusPhone() {
        launch(["BB_TEMP_UNIT": "c"])
        openEditor("Temperature")
        let bar = expect(app.navigationBars["New Temperature"])
        XCTAssertTrue(app.staticTexts["°C"].exists)
        let field = app.textFields["0"]
        field.tap()
        field.typeText("101.3")
        expect(app.staticTexts["101.3 looks like Fahrenheit. In Celsius that's 38.5°, over your fever line."])
        tap(app.buttons["Use 38.5°C"])
        expect(app.textFields.withValue("38.5"))
        tap(bar.buttons["Save"])
        expectGone(bar)
        expect(element(labeled: "Temperature, 38.5°C"))
        expect(element(labeled: "38.5°C is over the fever line"))
    }
}

extension UITestCase {
    /// On an open Duo, the app screenshot can read the dark front display.
    func attachSickSettingsScreen(_ name: String) {
        guard app.windows.firstMatch.frame.width >= 900, XCUIScreen.screens.count > 1,
              let innerScreen = XCUIScreen.screens.last else {
            attachScreen(name)
            return
        }
        let shot = XCTAttachment(screenshot: innerScreen.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

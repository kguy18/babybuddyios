import XCTest

/// What demo mode can't show: that the app and a real Baby Buddy server agree. Every assertion about
/// the server is made straight against its API, never through the app's own networking.
final class ServerTests: ServerTestCase {
    /// A mistyped token has to say so, not fail silently (#93, #94).
    func testBadTokenIsRejected() {
        launch(demo: false)
        let address = expect(app.textFields["Your server URL or IP address"])
        address.tap()
        address.typeText(api.baseURL.absoluteString)
        let token = app.secureTextFields["Paste your API token"]
        token.tap()
        token.typeText("not-a-real-token")
        tap(app.buttons["Connect"])

        expect(app.staticTexts["Your API token was rejected. Please sign in again."], timeout: 30)
        expect(app.buttons["Try again"])
    }

    /// Signing in downloads the server's data; signing out deletes the local copy (#87) and signing
    /// back in downloads it again.
    func testSignInSignOutAndBackIn() async throws {
        let child = try await api.firstChild()
        try await api.create("notes", ["child": child.id, "note": "\(marker) note", "time": Date().apiTime])

        signIn()
        expect(app.staticTexts[child.firstName])
        syncAndSearch(for: marker)
        expect(element(labeled: "Note, \(marker)"))

        tap(app.tabBars.buttons["Settings"])
        tap(app.buttons["Sign out"])
        tap(app.alerts.labeled("Sign out of ").buttons["Sign out"])
        expect(app.staticTexts["Connect to your self-hosted server"])

        connect()
        syncAndSearch(for: marker)
        expect(element(labeled: "Note, \(marker)"))
    }

    /// The offline-first round trip: what the app logs, edits and deletes reaches the server.
    func testRecordRoundTripsToServer() async throws {
        signIn()
        openEditor("Diaper")
        expect(app.navigationBars["New Diaper Change"])
        let note = app.textFields["Add a note…"]
        note.tap()
        note.typeText(marker)
        tap(app.buttons["Save Diaper Change"])

        let created = try await api.waitForRecord("changes", marker: marker)
        let id = try XCTUnwrap(created?["id"] as? Int, "The logged change never reached the server")

        syncAndSearch(for: marker)
        tap(element(labeled: "Diaper Change, "))
        expect(app.navigationBars["Edit Diaper Change"])
        // A filled field has no placeholder left to match on, so find it by what it holds. The
        // marker has to survive the edit: the teardown sweep and the search both hang off it.
        replaceText(app.textFields.withValue(marker), with: "\(marker) edited")
        tap(app.navigationBars["Edit Diaper Change"].buttons["Save"])
        let edited = try await api.waitForField("changes", id: id, field: "notes", contains: "edited")
        XCTAssertTrue(edited, "The edit never reached the server")

        tap(element(labeled: "Diaper Change, "))
        tap(app.buttons["Delete Diaper Change"])
        tap(app.alerts["Delete this diaper change?"].buttons["Delete"])
        let deleted = try await api.waitForDeletion("changes", id: id)
        XCTAssertTrue(deleted, "The delete never reached the server")
    }

    /// Regression: #5 — stopping a timer used to raise a conflict against the timer it had just
    /// consumed, on a real server only.
    func testStoppingTimerDoesNotRaiseConflict() async throws {
        signIn()
        tap(app.buttons["Add"])
        tap(app.buttons["Start timer"])
        expect(app.navigationBars["Start Timer"])
        let name = app.textFields["Optional"]
        name.tap()
        name.typeText(marker)
        tap(app.buttons["Sleep"])
        tap(app.buttons["Start sleep timer"])
        expect(element(labeled: "\(marker) running"))

        let timer = try await api.waitForRecord("timers", marker: marker)
        let timerID = try XCTUnwrap(timer?["id"] as? Int, "The timer never reached the server")
        let start = try XCTUnwrap(timer?["start"] as? String)

        tap(app.buttons["Stop"])
        tap(app.buttons["Log sleep"])
        expect(app.buttons.labeled("Start a timer"))

        let stopped = try await api.waitForDeletion("timers", id: timerID)
        XCTAssertTrue(stopped, "The stopped timer is still running on the server")
        let sleeps = try await api.list("sleep", ["limit": "20"])
        let logged = sleeps.first { $0["start"] as? String == start }
        XCTAssertNotNil(logged, "The timer's sleep never reached the server")
        if let id = logged?["id"] as? Int { try await api.delete("sleep", id: id) }

        tap(app.tabBars.buttons["Settings"])
        expect(app.staticTexts["All clear"])
    }

    /// Regression: #145 — a create that named its timer let the server replace the end with the
    /// moment the request arrived. The End chosen in the convert editor is the one saved.
    func testConvertedTimerKeepsEditedEnd() async throws {
        let target = Date().addingTimeInterval(-10 * 60)
        guard Calendar.current.isDateInToday(target) else {
            throw XCTSkip("Ten minutes ago was yesterday; the End row's date button would need changing too")
        }
        let child = try await api.firstChild()
        let timer = try await api.create("timers", [
            "child": child.id, "name": marker, "start": Date().addingTimeInterval(-60 * 60).apiTime,
        ])
        let timerID = try XCTUnwrap(timer["id"] as? Int)

        signIn()
        expect(element(labeled: "\(marker) running"))
        tap(app.buttons["Stop"])
        tap(app.buttons["Feeding"])
        tap(app.buttons["Log feeding…"])
        let note = expect(app.textFields["Add a note…"])
        note.tap()
        note.typeText("\(marker)\n")

        // End is the second picker; its buttons are the pair, the date, then the time.
        tap(app.datePickers.element(boundBy: 1).buttons.element(boundBy: 2))
        let wheels = app.pickerWheels
        expect(wheels.element(boundBy: 1))
        let format = DateFormatter()
        // Hour, minute, and AM/PM only on a 12-hour clock.
        let patterns: [String] = wheels.count == 3 ? ["h", "mm", "a"] : ["HH", "mm"]
        for (index, pattern) in patterns.enumerated() {
            format.dateFormat = pattern
            wheels.element(boundBy: index).adjust(toPickerWheelValue: format.string(from: target))
        }
        tap(app.buttons["PopoverDismissRegion"]) // close the wheels
        tap(app.buttons["Save Feeding"])

        let saved = try await api.waitForRecord("feedings", marker: marker)
        let end = try XCTUnwrap((saved?["end"] as? String).flatMap(Date.fromAPI), "The feeding never reached the server")
        let minute: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        XCTAssertEqual(Calendar.current.dateComponents(minute, from: end),
                       Calendar.current.dateComponents(minute, from: target),
                       "The server saved \(end), not the End chosen in the editor")
        let deleted = try await api.waitForDeletion("timers", id: timerID)
        XCTAssertTrue(deleted, "The converted timer is still running on the server")
    }

    /// #145 — a timer another device already logged is gone from the server. Logging it here parks
    /// the activity with the duplicate warning instead of posting a second copy.
    func testConvertingTimerGoneFromServerParks() async throws {
        let child = try await api.firstChild()
        let start = Date().addingTimeInterval(-20 * 60).apiTime
        let timer = try await api.create("timers", ["child": child.id, "name": marker, "start": start])
        let timerID = try XCTUnwrap(timer["id"] as? Int)

        signIn()
        expect(element(labeled: "\(marker) running"))
        try await api.delete("timers", id: timerID) // another device logs it first

        tap(app.buttons["Stop"])
        tap(app.buttons["Sleep"])
        tap(app.buttons["Log sleep"])

        tap(app.tabBars.buttons["Settings"])
        tap(app.buttons.labeled("Pending changes"), timeout: 40)
        expect(app.navigationBars["Pending Changes"])
        expect(app.buttons["Create without timer"], timeout: 40)
        expect(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'no longer exists on the server'")).firstMatch)
        let sleeps = try await api.list("sleep", ["limit": "20"])
        XCTAssertFalse(sleeps.contains { $0["start"] as? String == start }, "The parked sleep was posted anyway")

        app.staticTexts["Added Sleep"].swipeLeft()
        tap(app.buttons["Discard"])
        tap(app.alerts["Discard this change?"].buttons["Discard"])
    }

    /// A record changed on the server while this device was editing it is a conflict, and "Keep my
    /// version" sends the device's copy (#16).
    func testServerEditRaisesConflict() async throws {
        let child = try await api.firstChild()
        let start = Date().addingTimeInterval(-45 * 60)
        let feeding = try await api.create("feedings", [
            "child": child.id, "start": start.apiTime, "end": start.addingTimeInterval(15 * 60).apiTime,
            "type": "formula", "method": "bottle", "amount": 90, "notes": marker,
        ])
        let id = try XCTUnwrap(feeding["id"] as? Int)

        signIn()
        syncAndSearch(for: marker)
        expect(element(labeled: "Feeding, "))

        // Another device edits it between this one's pull and its push.
        try await api.patch("feedings", id: id, ["notes": "\(marker) from the server"])

        tap(element(labeled: "Feeding, "))
        expect(app.navigationBars["Edit Feeding"])
        replaceText(app.textFields.withValue(marker), with: "\(marker) from this device")
        tap(app.navigationBars["Edit Feeding"].buttons["Save"])

        tap(app.tabBars.buttons["Settings"])
        tap(app.buttons.labeled("Conflicts"), timeout: 40) // the row is only a button while one waits
        expect(app.navigationBars["Conflicts"])
        tap(app.buttons.labeled("Feeding"))
        expect(app.navigationBars["Resolve Conflict"])
        tap(app.buttons["Keep mine"])
        tap(app.buttons["Keep my version"])

        let mine = try await api.waitForField("feedings", id: id, field: "notes", contains: "from this device")
        XCTAssertTrue(mine, "Keeping my version should overwrite the server's")
    }

    /// Regression: #109 — a server rejection used to arrive with its HTML markup still in it. The
    /// row says it needs attention (not "waiting to sync"), and Pending Changes explains why.
    func testOverlapRejectionReadsCleanly() async throws {
        let child = try await api.firstChild()
        let start = Date().addingTimeInterval(-60 * 60)
        try await api.create("sleep", [
            "child": child.id, "start": start.apiTime,
            "end": Date().addingTimeInterval(-60).apiTime, "notes": marker,
        ])

        signIn()
        syncAndSearch(for: marker)
        let row = expect(element(labeled: "Sleep, "))

        // Repeating it keeps the duration and ends now, so it overlaps the entry it came from.
        row.swipeRight()
        let repeatAction = app.buttons["Repeat"]
        if repeatAction.waitForExistence(timeout: 2) { repeatAction.tap() }
        expect(elements("label BEGINSWITH 'Sleep, ' AND label CONTAINS 'sync needs attention'").firstMatch,
               timeout: 40)

        tap(app.tabBars.buttons["Settings"])
        tap(app.buttons.labeled("Pending changes"))
        expect(app.navigationBars["Pending Changes"])
        let reason = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] 'intersects'")).firstMatch
        expect(reason)
        XCTAssertFalse(reason.label.contains("<"), "The server's reason still carries HTML: \(reason.label)")

        // Leave nothing queued behind: the copy never reached the server, so discarding removes it.
        app.staticTexts["Added Sleep"].swipeLeft()
        tap(app.buttons["Discard"])
        tap(app.alerts["Discard this change?"].buttons["Discard"])
    }
}

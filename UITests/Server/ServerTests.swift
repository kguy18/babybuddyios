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
    /// consumed, on a real server only. Also #145/#146: Stop deletes the server timer at once, and
    /// the logged record ends at the Stop tap.
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

        // Stop alone stops it on the server (#146), before anything is logged.
        let stopTapped = Date()
        // The owner's device shares this server, so its running timers have a Stop here too.
        tap(app.buttons["Stop \(marker) running"])
        expect(app.navigationBars["Stop Timer"])
        let stopped = try await api.waitForDeletion("timers", id: timerID)
        XCTAssertTrue(stopped, "The stopped timer is still running on the server")

        // Log well after Stop: the sleep ends at the Stop tap, not when the server got it (#145).
        let loggedAfter = stopTapped.addingTimeInterval(20)
        while Date() < loggedAfter { try await Task.sleep(for: .seconds(1)) }
        tap(app.buttons["Log sleep"])
        expectGone(element(labeled: "\(marker) ")) // "Start a timer" only shows once no timer runs

        let logged = try await api.waitForRecord("sleep", marker: start)
        XCTAssertNotNil(logged, "The timer's sleep never reached the server")
        if let id = logged?["id"] as? Int { try await api.delete("sleep", id: id) }
        let end = try XCTUnwrap((logged?["end"] as? String).flatMap(Date.fromAPI))
        XCTAssertLessThan(end.timeIntervalSince(stopTapped), 10, "The sleep should end at Stop, not at Log")

        tap(app.tabBars.buttons["Settings"])
        expect(app.staticTexts["All clear"])
    }

    /// A record changed on the server while this device was editing it is a conflict, and "Keep my
    /// version" sends the device's copy (#16).
    func testServerEditRaisesConflict() async throws {
        let child = try await api.firstChild()
        // Any free quarter hour in the last 30 days will do, since the app pulls that far back.
        let slot = try await api.freeSlot("feedings", child: child.id, length: 15 * 60...15 * 60,
                                          before: Date().addingTimeInterval(-30 * 60))
        let feeding = try await api.create("feedings", [
            "child": child.id, "start": slot.start.apiTime, "end": slot.end.apiTime,
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
        // Repeat copies the sleep to end at the tap, with the same duration, and the server has to
        // refuse the copy for overlapping something. Usually that's the seed itself, filling the
        // free time up to a minute ago, so the copy covers its end. A sleep that ended in the last
        // ten minutes leaves no room there, so the seed goes further back and lasts an hour, and the
        // copy overlaps that recent sleep instead.
        let before = Date().addingTimeInterval(-60)
        var slot = try await api.freeSlot("sleep", child: child.id, length: 10 * 60...60 * 60, before: before)
        if slot.end < before {
            slot = try await api.freeSlot("sleep", child: child.id, length: 60 * 60...60 * 60, before: before)
        }
        try await api.create("sleep", [
            "child": child.id, "start": slot.start.apiTime, "end": slot.end.apiTime, "notes": marker,
        ])

        signIn()
        syncAndSearch(for: marker)
        let row = expect(element(labeled: "Sleep, "))

        // Repeating it keeps the duration and ends now, so it overlaps a sleep already there.
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

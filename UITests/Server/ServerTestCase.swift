import XCTest

/// Base for the tests that run against the demo Baby Buddy server — the only way to check that what
/// the app queues actually reaches a server, and that what a server says comes back readable.
///
/// `scripts/ui-test.sh --server` passes the server URL and the CI user's token as `TEST_RUNNER_`
/// variables (xcodebuild hands them to the runner with the prefix stripped). Without them these
/// tests skip, so the demo lane, a fork's PR and a plain `scripts/ui-test.sh` all stay green.
///
/// The server is shared — App Review signs into it too — so a test only ever asserts on records
/// carrying its own ``marker``, and deletes them afterwards. Children and tags are never touched.
@MainActor
class ServerTestCase: UITestCase {
    private(set) var api = BabyBuddyAPI(baseURL: URL(string: "https://unset.invalid")!, token: "")
    /// Stamped into everything this test writes: `ci-` plus eight characters.
    private(set) var marker = ""
    /// Swept after every test. Only kinds the suite writes.
    private let sweptPaths = ["feedings", "changes", "sleep", "notes", "timers", "tummy-times"]

    /// One probe per run, not per test: a server that's down shouldn't cost a timeout each time.
    private static var skipReason: String??

    /// Async, not `setUpWithError`: the probe has to be awaited. Blocking this thread for it
    /// deadlocks — the work is main-actor isolated too, so it can never run while this waits.
    override func setUp() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["BB_E2E_SERVER_URL"], let url = URL(string: address),
              let token = environment["BB_E2E_TOKEN"], !token.isEmpty else {
            throw XCTSkip("No demo server configured — run scripts/ui-test.sh --server")
        }
        api = BabyBuddyAPI(baseURL: url, token: token)
        if let reason = await Self.probeOnce(api) { throw XCTSkip(reason) }
        await Self.sweepOnce(api)

        marker = "ci-\(UUID().uuidString.prefix(8))"
        let api = api, marker = marker, paths = sweptPaths
        addTeardownBlock { await api.deleteMarked(in: paths, marker: marker) }
    }

    /// Clears timers an earlier run left running, once per run.
    ///
    /// `addTeardownBlock` only fires when a test finishes, so a run killed part-way — a cancelled
    /// CI job, a stopped `xcodebuild` — leaves its timer running on the shared server, where it
    /// shows on every signed-in device's Dashboard, App Review's included, until someone deletes it
    /// by hand. Sweeping before the first test cleans that up; per-test teardown still handles the
    /// normal path. The tests themselves tap their own timer's Stop, so a leftover can't break them.
    private static func sweepOnce(_ api: BabyBuddyAPI) async {
        guard !swept else { return }
        swept = true
        await api.deleteStaleTimers(prefix: "ci-")
    }

    private static var swept = false

    /// `nil` when the server is usable. A server that can't be reached skips the suite; a token it
    /// refuses doesn't — that's a broken secret, and silence would lose the coverage for good.
    private static func probeOnce(_ api: BabyBuddyAPI) async -> String? {
        if let decided = skipReason { return decided }
        switch await api.probe() {
        case .success:
            skipReason = .some(nil)
        case .failure(let failure) where failure.status == 401 || failure.status == 403:
            skipReason = .some(nil) // let the test fail on the rejected token, loudly
        case .failure(let failure):
            skipReason = .some("Demo server unreachable (\(failure.localizedDescription))")
        }
        return skipReason ?? nil
    }

    /// Signs in the way a customer does — the app has no other way in (#15).
    func signIn() {
        launch(demo: false)
        connect()
    }

    /// Fills in onboarding and connects, on whichever onboarding screen is showing — a fresh launch
    /// or the one left behind by signing out.
    func connect() {
        let address = expect(app.textFields["Your server URL or IP address"])
        address.tap()
        address.typeText(api.baseURL.absoluteString)
        let token = app.secureTextFields["Paste your API token"]
        token.tap()
        token.typeText(api.token)
        tap(app.buttons["Connect"])
        // The first pull brings the server's history down before the tabs appear.
        expect(app.tabBars.buttons["Home"], timeout: 60)
    }

    /// Pull to refresh on the Timeline, then find a record by its marker. The app syncs on its own
    /// schedule; this is the deliberate "fetch now" a customer would do.
    func syncAndSearch(for marker: String) {
        tap(app.tabBars.buttons["Timeline"])
        app.swipeDown()
        let search = app.searchFields.firstMatch
        tap(search)
        search.typeText("\(marker)\n")
    }
}

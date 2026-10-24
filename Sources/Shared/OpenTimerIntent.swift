import AppIntents

/// Opens the app on a running timer. The Quick start widget's running tiles use it: a small
/// widget ignores `Link`, so a per-tile tap has to be a `Button(intent:)`. The intent compiles
/// into the widget too and may run there, so it leaves the timer in ``SharedDefaults`` for the
/// app's ``DeepLinkRouter`` to take when it becomes active.
struct OpenTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open a timer"
    static var openAppWhenRun = true
    static var isDiscoverable = false

    @Parameter(title: "Timer ID")
    var timerLocalID: String

    init() {}
    init(timerLocalID: UUID) { self.timerLocalID = timerLocalID.uuidString }

    /// Set by the app, so a run in its own process routes without waiting for the next activation.
    @MainActor static var didRequestOpen: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let id = UUID(uuidString: timerLocalID) else { return .result() }
        SharedDefaults.pendingOpenTimerID = id
        Self.didRequestOpen?()
        return .result()
    }
}

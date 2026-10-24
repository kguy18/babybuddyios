import Network
import SwiftUI
import WebKit

/// Settings ▸ Feedback ▸ Send Feedback's three ways into the Quackback widget at
/// feedback.babybuddy.app, each in a sheet.
///
/// A plain WKWebView speaking the widget's `postMessage` protocol, not QuackbackIO/quackback-ios.
/// That package can't open the support conversation (its `OpenView` has no chat), its named
/// `identify` sends an unsigned id and email that the server rejects, and it presents its own
/// full-screen panel with no load-failure signal, so it can't sit in a sheet or fall back to Mail.
///
/// Identity: anonymous until someone signs in with ``FeedbackSignInView``, plus a random
/// per-install ID (`quackback:device`). Nothing else about the user is sent.
enum FeedbackWidget: String, Identifiable {
    case board, help, roadmap

    var id: Self { self }

    var title: String {
        switch self {
        case .board: "Request a Feature"
        case .help: "Get Help"
        case .roadmap: "Roadmap and Updates"
        }
    }

    /// The widget view `quackback:open` lands on. Quackback 0.14.1 has no plain Feedback view to
    /// open; `new-post` is the one that lands on the Feedback tab, with "What's your idea?" opened.
    /// `chat` opens Messages, the support thread, and `home` the widget's Home.
    fileprivate var view: String {
        switch self {
        case .board: "new-post"
        case .help: "chat"
        case .roadmap: "home"
        }
    }

    /// `BB_FEEDBACK=<url>` points the widget at another server; the UI tests pass an unreachable
    /// one to reach the Mail fallback.
    static let serverURL = ProcessInfo.processInfo.environment["BB_FEEDBACK"].flatMap(URL.init(string:))
        ?? URL(string: "https://feedback.babybuddy.app")!

    /// Random, made on first open, kept in standard defaults so it goes away with the app.
    fileprivate static var installID: String {
        let key = "feedbackInstallID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }

    fileprivate var widgetURL: URL {
        var components = URLComponents(url: Self.serverURL, resolvingAgainstBaseURL: false)!
        components.path = "/widget"
        // `source=native` makes the widget post its events to `window.__quackbackNative`.
        components.queryItems = [URLQueryItem(name: "source", value: "native"),
                                 URLQueryItem(name: "platform", value: "ios")]
        return components.url!
    }

    /// Sent once the widget reports `ready`. `quackback:mobile` hides the widget's panel-size
    /// control, which means nothing in a sheet.
    ///
    /// No `quackback:identify`: the widget is anonymous until someone signs in, and mints its
    /// anonymous session on the first write. An anonymous identify also broke sign-in, because
    /// Quackback 0.14.1 answers it, for a widget already on a portal session, with an
    /// `auth-change` carrying a stale `null` user, so a signed-in user looked signed out.
    fileprivate var setupScript: String {
        let messages = [
            "{type:'quackback:mobile',data:true}",
            "{type:'quackback:device',data:'\(Self.installID)'}",
            "{type:'quackback:open',data:{view:'\(view)'}}",
        ]
        return messages.map { "window.postMessage(\($0),'*');" }.joined()
    }

    fileprivate static func isOnServer(_ url: URL) -> Bool {
        url.host == serverURL.host
    }

    /// The widget's own pages, the only ones the sheet loads. Other pages on the server open in
    /// Safari, and its sign-in pages open the native sign-in.
    fileprivate static func isWidgetPage(_ url: URL) -> Bool {
        isOnServer(url) && url.path.hasPrefix("/widget")
    }

    /// Quackback's sign-in pages: `/auth/...`, and the portal root with its `auth` dialog request
    /// (`/auth/login` redirects to `/?auth=signin&callbackUrl=...`). A widget link to one opens
    /// the native sign-in instead.
    static func isSignInURL(_ url: URL) -> Bool {
        guard isOnServer(url) else { return false }
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.path ?? url.path
        return path == "/auth" || path.hasPrefix("/auth/")
            || (path == "/" || path.isEmpty) && (components?.queryItems ?? []).contains { $0.name == "auth" }
    }

    /// Every widget load in the sheet goes through here, so the UI-test stub can stand in for it.
    @MainActor fileprivate static func load(_ url: URL, in webView: WKWebView) {
        if isStubbed {
            Task {
                let signedIn = await FeedbackSession.isSignedIn
                webView.loadHTMLString(stubPage(signedIn: signedIn), baseURL: url)
            }
        } else {
            webView.load(URLRequest(url: url, timeoutInterval: 8))
        }
    }

    // MARK: UI-test stub

    /// `BB_FEEDBACK_STUB=signed-out|signed-in`, honored only with `BB_UITEST`: the sheet's widget
    /// and the sign-in calls (``FeedbackSession``) come from stubs instead of the network, so UI
    /// tests reach their states offline. `signed-in` starts the launch with a stub session.
    static let stubMode = ProcessInfo.processInfo.environment["BB_UITEST"] == "1"
        ? ProcessInfo.processInfo.environment["BB_FEEDBACK_STUB"] : nil
    static let isStubbed = stubMode == "signed-out" || stubMode == "signed-in"

    /// The widget page plays the real one's part over the same bridge. Like Quackback 0.14.1, it
    /// reports a session's user with `auth-change` before `ready` and says nothing for an
    /// anonymous visitor; it has a session when the web view's cookie store holds one, as the
    /// native sign-in leaves it. It shows the `quackback:open` view it's sent so a test can read it,
    /// and a "Sign in to post" link to the portal's sign-in, as the real board has.
    private static func stubPage(signedIn: Bool) -> String {
        """
        <p id="view">Stub widget</p>
        <p><a href="/?auth=signin">Sign in to post</a></p>
        <script>
        window.addEventListener('message', function (e) {
            if (e.data && e.data.type === 'quackback:open') {
                document.getElementById('view').textContent = 'Stub widget: ' + e.data.data.view;
            }
        });
        \(signedIn ? "window.__quackbackNative.dispatch('auth-change', { user: { id: 'stub' } });" : "")
        window.__quackbackNative.dispatch('ready', {});
        </script>
        """
    }
}

struct FeedbackSheet: View {
    let widget: FeedbackWidget
    /// "Email Support" on the unreachable screen, just before the sheet closes. The caller offers Mail.
    let onEmail: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase = FeedbackWebView.Phase.loading
    /// Whether the widget has a signed-in user, from its `auth-change` event; `nil` until it says.
    @State private var signedIn: Bool?
    /// The native sign-in, pushed over the widget.
    @State private var signingIn = false
    /// Bumped after a sign-in; the web view reloads the widget, which then starts signed in.
    @State private var reloads = 0
    /// A sign-in's session is going into the web view's cookie store.
    @State private var savingSession = false

    /// Quackback 0.14.1 disables Submit for a signed-out visitor on a board that needs sign-in
    /// and shows "Sign in to post on this board" as plain text, so the board needs a way in. Get
    /// Help shows the sign-in in place of the chat instead.
    private var showsSignIn: Bool {
        phase == .ready && signedIn == false && widget != .help
    }

    /// Get Help needs a signed-in user, so every chat has an email to reply to. Quackback's chat
    /// takes anonymous messages and 0.14.1 has no setting to stop that, so the sheet holds the
    /// chat back until the widget reports a user, and shows a signed-out one the sign-in.
    private var holdsChat: Bool {
        widget == .help && signedIn != true
    }

    /// The web view shows once the widget is ready, except a held chat.
    private var showsWebView: Bool {
        phase == .ready && !holdsChat && !savingSession
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BBColor.surface.ignoresSafeArea()
                if phase == .failed {
                    unreachable
                } else {
                    FeedbackWebView(widget: widget, phase: $phase, signedIn: $signedIn, reloads: reloads,
                                    onSignIn: { if widget != .help, signedIn != true { signingIn = true } },
                                    onClose: { dismiss() })
                        .opacity(showsWebView ? 1 : 0)
                        .accessibilityHidden(!showsWebView)
                        .allowsHitTesting(showsWebView)
                    if phase == .loading || savingSession || (phase == .ready && holdsChat && signedIn == nil) {
                        ProgressView()
                    } else if phase == .ready && holdsChat {
                        signIn
                    }
                }
            }
            // The presenting screen's toast is under the sheet; "App details copied" shows here.
            .overlay(alignment: .bottom) { UndoToastView().padding(.bottom, 12) }
            .navigationTitle(widget.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if widget == .help {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            UIPasteboard.general.string = SupportContact.diagnostics
                            UndoToastCenter.shared.confirm("App details copied")
                        } label: {
                            Label("Copy App Details", systemImage: "doc.on.doc")
                        }
                    }
                }
                if showsSignIn {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sign In") { signingIn = true }
                    }
                }
            }
            .navigationDestination(isPresented: $signingIn) {
                signIn
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } }
                    }
            }
        }
    }

    /// The native sign-in. Once it has written the session, the widget reloads and starts signed
    /// in, on the sheet's view. Offline, the sheet shows its Mail fallback.
    private var signIn: some View {
        FeedbackSignInView(widget: widget, onSignedIn: { session in
            // Back to the widget first. While its web view is off screen WebKit can hold up the
            // cookie write, by 20 seconds and more in testing.
            signingIn = false
            signedIn = nil
            savingSession = true
            Task {
                await FeedbackSession.save(session)
                feedbackTrace("signed in: reloading the widget")
                savingSession = false
                reloads += 1
            }
        }, onUnreachable: {
            signingIn = false
            phase = .failed
        })
    }

    private var unreachable: some View {
        BBCard(cornerRadius: BBRadius.card, padding: 20) {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(BBColor.brand)
                    .accessibilityHidden(true)
                Text("Can't reach the feedback server")
                    .font(.headline)
                Text("Check your connection, or email us and we'll reply there.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Email Support") { onEmail(); dismiss() }
                    .buttonStyle(.bbPrimary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
    }
}

/// The widget page. Reports `ready` once the widget says so, and `failed` at once when the device
/// is offline or the page can't load or returns an HTTP error, or after `readyTimeout` for a slow
/// server.
struct FeedbackWebView: UIViewRepresentable {
    enum Phase { case loading, ready, failed }

    static let readyTimeout: Duration = .seconds(8)

    /// The widget's own X, which would sit beside the sheet's Close. Quackback 0.14.1 has no setting
    /// to hide it when hosted natively, so this matches the header button that holds the X icon
    /// (heroicons' XMarkIcon path) rather than its aria-label, which the widget translates. Its
    /// `close` event still dismisses the sheet if a later widget brings it back.
    private static let hideCloseButtonCSS = #"button.h-8.w-8:has(> svg.w-5 > path[d^="M5.47 5.47"]) { display: none !important; }"#

    let widget: FeedbackWidget
    @Binding var phase: Phase
    @Binding var signedIn: Bool?
    let reloads: Int
    /// The widget linked to Quackback's sign-in page.
    let onSignIn: () -> Void
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        // The widget calls `__quackbackNative.dispatch(event, message)` for ready, close, navigate.
        content.addUserScript(WKUserScript(source: """
            window.__quackbackNative = { dispatch: function (event, message) {
                window.webkit.messageHandlers.quackback.postMessage(
                    { event: event, url: (message && typeof message.url === 'string') ? message.url : '',
                      signedIn: !!(message && message.user),
                      detail: (message && typeof message.detail === 'string') ? message.detail : '' });
            } };
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #if DEBUG
        // DEBUG trace: every history change, including the widget's client-side navigations.
        content.addUserScript(WKUserScript(source: """
            (function () {
                var trace = function (what) {
                    window.__quackbackNative.dispatch('trace', { detail: what, url: location.href });
                };
                ['pushState', 'replaceState'].forEach(function (name) {
                    var original = history[name];
                    history[name] = function () {
                        var result = original.apply(this, arguments);
                        trace(name);
                        return result;
                    };
                });
                window.addEventListener('popstate', function () { trace('popstate'); });
            })();
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #endif
        content.addUserScript(WKUserScript(source: """
            if (location.pathname.indexOf('/widget') === 0) {
                var style = document.createElement('style');
                style.textContent = '\(Self.hideCloseButtonCSS)';
                document.head.appendChild(style);
            }
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        content.add(context.coordinator, name: "quackback")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content
        // Persistent: the sign-in's session cookie lives here and survives relaunches.
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        #if DEBUG
        webView.isInspectable = true // so Safari's Web Inspector can attach on a device
        #endif
        feedbackTrace("open \(widget.rawValue) sheet: \(FeedbackTrace.clean(widget.widgetURL))")
        FeedbackWidget.load(widget.widgetURL, in: webView)
        context.coordinator.startWatching()
        return webView
    }

    /// The reload runs on the next turn of the main queue, so its state writes don't land inside
    /// this view update and get dropped.
    func updateUIView(_ webView: WKWebView, context: Context) {
        guard reloads != context.coordinator.handledReloads else { return }
        context.coordinator.handledReloads = reloads
        DispatchQueue.main.async { FeedbackWidget.load(widget.widgetURL, in: webView) }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "quackback")
        coordinator.readyTimer?.cancel()
        coordinator.pathMonitor.cancel()
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let parent: FeedbackWebView
        var readyTimer: Task<Void, Never>?
        let pathMonitor = NWPathMonitor()
        var handledReloads = 0

        init(_ parent: FeedbackWebView) { self.parent = parent }

        /// Fails at once when the first network path reading says offline, otherwise after
        /// `readyTimeout` without a `ready`.
        func startWatching() {
            pathMonitor.pathUpdateHandler = { [weak self] path in
                MainActor.assumeIsolated {
                    self?.pathMonitor.cancel()
                    if path.status != .satisfied { feedbackTrace("offline"); self?.fail() }
                }
            }
            // The stub needs no network, so a test run offline must not fail on the path check.
            if !FeedbackWidget.isStubbed { pathMonitor.start(queue: .main) }
            readyTimer = Task { @MainActor [weak self] in
                try? await Task.sleep(for: FeedbackWebView.readyTimeout)
                guard !Task.isCancelled, let self, self.parent.phase == .loading else { return }
                feedbackTrace("phase = failed (no ready in time)")
                self.parent.phase = .failed
            }
        }

        /// Quackback's sign-in pages open the native sign-in, the widget's pages load here, and
        /// anything else, portal pages included, opens in Safari.
        private func open(_ url: URL, in webView: WKWebView?) {
            if FeedbackWidget.isSignInURL(url) {
                feedbackTrace("widget asked for sign-in")
                parent.onSignIn()
            } else if FeedbackWidget.isWidgetPage(url), let webView {
                FeedbackWidget.load(url, in: webView)
            } else {
                UIApplication.shared.open(url)
            }
        }

        private func fail() {
            readyTimer?.cancel()
            guard parent.phase == .loading else { return }
            feedbackTrace("phase = failed")
            parent.phase = .failed
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
            // Only the event, the cleaned URL and the signed-in flag: never the user object.
            feedbackTrace("bridge \(event)"
                + ((body["detail"] as? String).map { $0.isEmpty ? "" : " \($0)" } ?? "")
                + ((body["url"] as? String).map { $0.isEmpty ? "" : " \(FeedbackTrace.clean(URL(string: $0)))" } ?? "")
                + (event == "auth-change" ? " signedIn=\(body["signedIn"] as? Bool ?? false)" : ""))
            switch event {
            case "ready":
                readyTimer?.cancel()
                // Quackback reports a session's user before `ready`, and nothing for an anonymous
                // visitor.
                if parent.signedIn == nil {
                    feedbackTrace("no user before ready: signed out")
                    parent.signedIn = false
                }
                message.webView?.evaluateJavaScript(parent.widget.setupScript)
                if parent.phase != .ready { feedbackTrace("phase = ready") }
                parent.phase = .ready
            case "close":
                parent.onClose()
            case "auth-change":
                parent.signedIn = body["signedIn"] as? Bool ?? false
            case "navigate":
                if let url = URL(string: body["url"] as? String ?? ""), ["https", "http"].contains(url.scheme) {
                    open(url, in: message.webView)
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            feedbackTrace("didCommit \(FeedbackTrace.clean(webView.url))")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            feedbackTrace("didFailProvisional \((error as NSError).domain) \((error as NSError).code)")
            fail()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            feedbackTrace("didFail \((error as NSError).domain) \((error as NSError).code)")
            fail()
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
                feedbackTrace("HTTP \(http.statusCode) for \(FeedbackTrace.clean(response.response.url))")
                fail()
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// A tapped link that leaves the widget goes through `open(_:in:)`.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url,
               !FeedbackWidget.isWidgetPage(url) {
                decisionHandler(.cancel)
                open(url, in: webView)
                return
            }
            decisionHandler(.allow)
        }

        /// `target="_blank"` links.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { open(url, in: webView) }
            return nil
        }
    }
}

/// A trace line for the DEBUG feedback trace; compiled to nothing in release builds.
@inline(__always) func feedbackTrace(_ message: @autoclosure () -> String) {
    #if DEBUG
    FeedbackTrace.log(message())
    #endif
}

/// DEBUG only: one line per feedback-sheet event in `Documents/feedback-trace.log`, to see what a
/// real sign-in does on a device. URLs keep only the `auth`, `callbackUrl`, `board` and `source`
/// query parameters, and nothing logs cookies, emails, codes, passwords or the widget's user
/// object.
enum FeedbackTrace {
    static func clean(_ url: URL?) -> String {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return "nil" }
        let kept = (components.queryItems ?? []).filter { ["auth", "callbackUrl", "board", "source"].contains($0.name) }
        components.queryItems = kept.isEmpty ? nil : kept
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.string ?? "?"
    }

    #if DEBUG
    static let file = URL.documentsDirectory.appending(path: "feedback-trace.log")

    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func log(_ message: String) {
        guard let data = "\(timestamp.string(from: Date())) \(message)\n".data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: file) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: file)
        }
    }
    #endif
}

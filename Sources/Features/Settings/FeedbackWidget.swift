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
/// Identity: the widget's anonymous session plus a random per-install ID (`quackback:device`).
/// Nothing else about the user is sent.
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

    /// Whether `url` is the feedback server itself, which loads inside the sheet. Anything else
    /// opens in Safari.
    fileprivate static func isOnServer(_ url: URL) -> Bool {
        url.host == serverURL.host
    }

    /// Quackback's sign-in pages: `/auth/...`, and the portal root with its `auth` dialog request
    /// (`/auth/login` redirects to `/?auth=signin&callbackUrl=...`).
    static func isSignInURL(_ url: URL) -> Bool {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let path = components?.path ?? url.path
        return path == "/auth" || path.hasPrefix("/auth/")
            || (path == "/" || path.isEmpty) && (components?.queryItems ?? []).contains { $0.name == "auth" }
    }

    /// A page on the server that the sheet shouldn't stay on: neither a sign-in page nor the app's
    /// own widget URL. That's where a sign-in ends, wherever the portal landed (`/`, a board, a
    /// bare `/widget`), and the sheet then reloads the widget on its view.
    static func isPortalPage(_ url: URL) -> Bool {
        guard isOnServer(url), !isSignInURL(url) else { return false }
        return !(url.path.hasPrefix("/widget") && url.query?.contains("source=native") == true)
    }

    /// Quackback's sign-in, kept inside the sheet so its session cookie lands in the web view the
    /// widget reads. On success the portal client-navigates to `callbackUrl`, so it points at
    /// `/widget`; `isPortalPage(_:)` covers any other landing.
    static func inSheetURL(for url: URL) -> URL {
        guard isSignInURL(url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        let query = components.queryItems ?? []
        guard !query.contains(where: { $0.name == "callbackUrl" }) else { return url }
        components.queryItems = query + [URLQueryItem(name: "callbackUrl", value: "/widget")]
        return components.url ?? url
    }

    /// Every page load in the sheet goes through here, so the UI-test stub can stand in for them.
    @MainActor fileprivate static func load(_ url: URL, in webView: WKWebView) {
        if isStubbed {
            if isPortalPage(url), !url.path.hasPrefix("/widget") { stubSignedIn = true }
            webView.loadHTMLString(stubPage(for: url), baseURL: url)
        } else {
            webView.load(URLRequest(url: url, timeoutInterval: 8))
        }
    }

    // MARK: UI-test stub

    /// `BB_FEEDBACK_STUB=signed-out|signed-in`, honored only with `BB_UITEST`: the sheet's pages
    /// come from `stubPage(for:)` instead of the network, so UI tests reach its states offline.
    private static let stubMode = ProcessInfo.processInfo.environment["BB_UITEST"] == "1"
        ? ProcessInfo.processInfo.environment["BB_FEEDBACK_STUB"] : nil
    fileprivate static let isStubbed = stubMode == "signed-out" || stubMode == "signed-in"

    /// Starts as the stub mode says, and turns on once the stub's "Signed in" link lands on a
    /// portal page, as a real sign-in would.
    @MainActor private static var stubSignedIn = stubMode == "signed-in"

    /// The widget page plays the real one's part over the same bridge. Like Quackback 0.14.1, it
    /// reports a portal session's user with `auth-change` before `ready` and says nothing for an
    /// anonymous visitor. It shows the `quackback:open` view it's sent so a test can read it. A
    /// sign-in page has a "Signed in" link to the portal root; any other page stands in for the
    /// portal.
    @MainActor private static func stubPage(for url: URL) -> String {
        if isSignInURL(url) { return #"<p>Sign-in stub</p><p><a href="/">Signed in</a></p>"# }
        guard url.path.hasPrefix("/widget") else { return "<p>Portal stub</p>" }
        return """
            <p id="view">Stub widget</p>
            <script>
            window.addEventListener('message', function (e) {
                if (e.data && e.data.type === 'quackback:open') {
                    document.getElementById('view').textContent = 'Stub widget: ' + e.data.data.view;
                }
            });
            \(stubSignedIn ? "window.__quackbackNative.dispatch('auth-change', { user: { id: 'stub' } });" : "")
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
    /// The web view is on another page of the feedback server (the sign-in), not the widget.
    @State private var awayFromWidget = false
    /// Bumped by Back; the web view reloads the widget on the same view.
    @State private var backRequests = 0
    /// Whether the widget has a signed-in user, from its `auth-change` event; `nil` until it says.
    @State private var signedIn: Bool?
    /// Bumped by Sign In; the web view opens Quackback's sign-in.
    @State private var signInRequests = 0

    /// Quackback 0.14.1 disables Submit for a signed-out visitor on a board that needs sign-in
    /// and shows "Sign in to post on this board" as plain text, so the board needs a way in.
    private var showsSignIn: Bool {
        phase == .ready && !awayFromWidget && signedIn == false
    }

    /// Get Help needs a signed-in user, so every chat has an email to reply to. Quackback's chat
    /// takes anonymous messages and 0.14.1 has no setting to stop that, so the sheet holds the
    /// chat back until the widget reports a user, and asks a signed-out one to sign in first.
    private var holdsChat: Bool {
        widget == .help && !awayFromWidget && signedIn != true
    }

    /// The web view shows once the widget is ready, except a held chat.
    private var showsWebView: Bool {
        phase == .ready && !holdsChat
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BBColor.surface.ignoresSafeArea()
                if phase == .failed {
                    unreachable
                } else {
                    FeedbackWebView(widget: widget, phase: $phase, awayFromWidget: $awayFromWidget,
                                    signedIn: $signedIn, backRequests: backRequests,
                                    signInRequests: signInRequests, onClose: { dismiss() })
                        .opacity(showsWebView ? 1 : 0)
                        .accessibilityHidden(!showsWebView)
                        .allowsHitTesting(showsWebView)
                    if phase == .loading || (phase == .ready && holdsChat && signedIn == nil) {
                        ProgressView()
                    } else if phase == .ready && holdsChat {
                        signInFirst
                    }
                }
            }
            .navigationTitle(widget.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                if showsSignIn {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Sign In") { signInRequests += 1 }
                    }
                }
                if awayFromWidget {
                    ToolbarItem(placement: .topBarLeading) {
                        // Back from Get Help's sign-in closes the sheet: the chat behind it is
                        // the anonymous one this sheet won't show.
                        Button { if widget == .help { dismiss() } else { backRequests += 1 } } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }
                    }
                }
            }
        }
    }

    /// Get Help before sign-in.
    private var signInFirst: some View {
        BBCard(cornerRadius: BBRadius.card, padding: 20) {
            VStack(spacing: 12) {
                Image(systemName: "envelope")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(BBColor.brand)
                    .accessibilityHidden(true)
                Text("Sign in with your email so I can reply to you.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text("No password needed. You'll get a code by email.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Sign In with Email") { signInRequests += 1 }
                    .buttonStyle(.bbPrimary)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
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
    @Binding var awayFromWidget: Bool
    @Binding var signedIn: Bool?
    let backRequests: Int
    let signInRequests: Int
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
            // The portal's sign-in dialog announces success on this channel, and may not
            // navigate at all afterwards.
            if (typeof BroadcastChannel === 'undefined') {
                window.__quackbackNative.dispatch('trace', { detail: 'BroadcastChannel undefined' });
            } else {
                try {
                    new BroadcastChannel('quackback-auth').onmessage = function (e) {
                        if (e.data && e.data.type === 'auth-success') window.__quackbackNative.dispatch('signed-in', {});
                    };
                } catch (e) {
                    window.__quackbackNative.dispatch('trace', { detail: 'BroadcastChannel threw: ' + e.name });
                }
            }
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #if DEBUG
        // DEBUG trace: every history change, including the portal's client-side navigations.
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
        // Persistent, so a Quackback sign-in survives relaunches.
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
        context.coordinator.startWatching(webView)
        return webView
    }

    /// Loads run on the next turn of the main queue: `load` changes `url` at once, and the
    /// observer's state writes would otherwise land inside this view update and be dropped.
    func updateUIView(_ webView: WKWebView, context: Context) {
        var next: URL?
        if backRequests != context.coordinator.handledBackRequests {
            context.coordinator.handledBackRequests = backRequests
            feedbackTrace("Back: reloading the widget")
            context.coordinator.signInStarted = false
            next = widget.widgetURL
        }
        if signInRequests != context.coordinator.handledSignInRequests {
            context.coordinator.handledSignInRequests = signInRequests
            if signedIn == true {
                // Already signed in: Quackback's sign-in would just land on the portal.
                feedbackTrace("Sign In tapped while signed in: reloading the widget")
                next = widget.widgetURL
            } else {
                feedbackTrace("Sign In tapped")
                context.coordinator.signInStarted = true
                next = FeedbackWidget.inSheetURL(for: FeedbackWidget.serverURL.appending(path: "auth/login"))
            }
        }
        if let next {
            DispatchQueue.main.async { FeedbackWidget.load(next, in: webView) }
        }
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "quackback")
        coordinator.readyTimer?.cancel()
        coordinator.pathMonitor.cancel()
        coordinator.urlObservation = nil
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let parent: FeedbackWebView
        var readyTimer: Task<Void, Never>?
        let pathMonitor = NWPathMonitor()
        var urlObservation: NSKeyValueObservation?
        var handledBackRequests = 0
        var handledSignInRequests = 0
        /// Reloads of the widget since its last `ready`, so a server that keeps redirecting it to the
        /// portal can't loop.
        var returnsWithoutReady = 0
        /// Set when a sign-in starts; the next sign-in-finished signal returns to the widget.
        var signInStarted = false {
            didSet { if signInStarted != oldValue { feedbackTrace("signInStarted = \(signInStarted)") } }
        }

        init(_ parent: FeedbackWebView) { self.parent = parent }

        /// Fails at once when the first network path reading says offline, otherwise after
        /// `readyTimeout` without a `ready`.
        func startWatching(_ webView: WKWebView) {
            // `url` also changes on the portal's client-side navigation after sign-in, which no
            // navigation delegate call reports.
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.urlChanged(webView) }
            }
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

        /// Tracks whether the sheet is off the widget, and returns to it once a sign-in is over.
        /// Client-side navigations change `url` without a delegate call, hence the observer.
        private func urlChanged(_ webView: WKWebView) {
            feedbackTrace("url = \(FeedbackTrace.clean(webView.url))")
            guard let url = webView.url, FeedbackWidget.isOnServer(url) else { return }
            let onWidget = url.path.hasPrefix("/widget")
            if parent.awayFromWidget == onWidget {
                feedbackTrace("awayFromWidget = \(!onWidget)")
                parent.awayFromWidget = !onWidget
            }
            if FeedbackWidget.isSignInURL(url) { signInStarted = true }
            // Wherever the sheet lands on the portal, after a sign-in or not, it goes back to the
            // widget, so it never stays on the portal board.
            if FeedbackWidget.isPortalPage(url) {
                guard returnsWithoutReady < 3 else {
                    feedbackTrace("on the portal at \(FeedbackTrace.clean(url)), not reloading again")
                    return
                }
                returnsWithoutReady += 1
                feedbackTrace((signInStarted ? "sign-in finished at " : "on the portal at ")
                    + FeedbackTrace.clean(url))
                returnToWidget(webView)
            }
        }

        /// A full load of the widget URL: its server render picks up the new session, and
        /// `ready` re-opens the sheet's view.
        private func returnToWidget(_ webView: WKWebView) {
            feedbackTrace("reloading the widget")
            signInStarted = false
            FeedbackWidget.load(parent.widget.widgetURL, in: webView)
        }

        /// Sign-in pages and the widget load here; anything else, other portal pages included,
        /// opens in Safari, since the sheet goes back to the widget from any portal page.
        private func open(_ url: URL, in webView: WKWebView?) {
            if FeedbackWidget.isOnServer(url), !FeedbackWidget.isPortalPage(url) || url.path.hasPrefix("/widget"),
               let webView {
                if FeedbackWidget.isSignInURL(url) { signInStarted = true }
                FeedbackWidget.load(FeedbackWidget.inSheetURL(for: url), in: webView)
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
                returnsWithoutReady = 0
                // Quackback reports a portal session's user before `ready`, and nothing for an
                // anonymous visitor.
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
            case "signed-in":
                if signInStarted, let webView = message.webView {
                    feedbackTrace("sign-in finished by broadcast")
                    returnToWidget(webView)
                }
            case "navigate":
                if let url = URL(string: body["url"] as? String ?? ""), ["https", "http"].contains(url.scheme) {
                    open(url, in: message.webView)
                }
            default:
                break
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            feedbackTrace("didStart \(FeedbackTrace.clean(webView.url))")
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            feedbackTrace("didCommit \(FeedbackTrace.clean(webView.url))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            feedbackTrace("didFinish \(FeedbackTrace.clean(webView.url))")
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
            feedbackTrace("decide response \(FeedbackTrace.clean(response.response.url))"
                + " status=\((response.response as? HTTPURLResponse)?.statusCode ?? 0) mainFrame=\(response.isForMainFrame)")
            if response.isForMainFrame, let http = response.response as? HTTPURLResponse, http.statusCode >= 400 {
                fail()
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// Links off the feedback server open in Safari rather than replacing the widget.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            feedbackTrace("decide action \(FeedbackTrace.clean(action.request.url))"
                + " type=\(action.navigationType.rawValue) mainFrame=\(action.targetFrame?.isMainFrame ?? false)")
            // The stub's pages are inline, so its links load the next stub page, not the network.
            if FeedbackWidget.isStubbed, action.navigationType == .linkActivated, let url = action.request.url {
                decisionHandler(.cancel)
                FeedbackWidget.load(url, in: webView)
                return
            }
            if action.navigationType == .linkActivated, let url = action.request.url,
               !FeedbackWidget.isOnServer(url) || FeedbackWidget.isPortalPage(url) && !url.path.hasPrefix("/widget") {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// `target="_blank"` links: the server's own pages load here, others in Safari.
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
/// query parameters, and nothing logs cookies, codes or the widget's user object.
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

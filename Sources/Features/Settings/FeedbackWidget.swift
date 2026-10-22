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
    fileprivate var setupScript: String {
        let messages = [
            "{type:'quackback:mobile',data:true}",
            #"{type:'quackback:identify',data:{anonymous:true}}"#,
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

    /// Quackback's sign-in, kept inside the sheet so its session cookie lands in the web view the
    /// widget reads. A signed-out Submit or Vote asks to navigate to `/auth/login`, which
    /// redirects to the portal's sign-in dialog and, on success, client-navigates to `callbackUrl`.
    /// Pointing that at `/widget` brings the user back here (see `Coordinator.urlChanged`).
    static func inSheetURL(for url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        let query = components.queryItems ?? []
        let isSignIn = components.path == "/auth/login"
            || (components.path == "/" && query.contains { $0.name == "auth" })
        guard isSignIn, !query.contains(where: { $0.name == "callbackUrl" }) else { return url }
        components.queryItems = query + [URLQueryItem(name: "callbackUrl", value: "/widget")]
        return components.url ?? url
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
                      signedIn: !!(message && message.user) });
            } };
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
        webView.load(URLRequest(url: widget.widgetURL, timeoutInterval: 8))
        context.coordinator.startWatching(webView)
        return webView
    }

    /// Loads run on the next turn of the main queue: `load` changes `url` at once, and the
    /// observer's state writes would otherwise land inside this view update and be dropped.
    func updateUIView(_ webView: WKWebView, context: Context) {
        var next: URL?
        if backRequests != context.coordinator.handledBackRequests {
            context.coordinator.handledBackRequests = backRequests
            next = widget.widgetURL
        }
        if signInRequests != context.coordinator.handledSignInRequests {
            context.coordinator.handledSignInRequests = signInRequests
            next = FeedbackWidget.inSheetURL(for: FeedbackWidget.serverURL.appending(path: "auth/login"))
        }
        if let next {
            DispatchQueue.main.async { webView.load(URLRequest(url: next)) }
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
                    if path.status != .satisfied { self?.fail() }
                }
            }
            pathMonitor.start(queue: .main)
            readyTimer = Task { @MainActor [weak self] in
                try? await Task.sleep(for: FeedbackWebView.readyTimeout)
                guard !Task.isCancelled, let self, self.parent.phase == .loading else { return }
                self.parent.phase = .failed
            }
        }

        /// Tracks whether the sheet is off the widget, and returns to it after sign-in: the portal
        /// lands on a bare `/widget`, without `source=native`, so the widget would neither report
        /// to the app nor open the right view. A full load of the widget URL fixes both, and its
        /// server-side render picks up the new session.
        private func urlChanged(_ webView: WKWebView) {
            guard let url = webView.url, FeedbackWidget.isOnServer(url) else { return }
            let onWidget = url.path.hasPrefix("/widget")
            let wasAway = parent.awayFromWidget
            if wasAway == onWidget { parent.awayFromWidget = !onWidget }
            // Only on the way back from another page, so the widget's own URL changes never loop.
            if onWidget, wasAway, url.query?.contains("source=native") != true {
                webView.load(URLRequest(url: parent.widget.widgetURL))
            }
        }

        /// Pages on the feedback server load here; anything else opens in Safari.
        private func open(_ url: URL, in webView: WKWebView?) {
            if FeedbackWidget.isOnServer(url), let webView {
                webView.load(URLRequest(url: FeedbackWidget.inSheetURL(for: url)))
            } else {
                UIApplication.shared.open(url)
            }
        }

        private func fail() {
            readyTimer?.cancel()
            guard parent.phase == .loading else { return }
            parent.phase = .failed
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let event = body["event"] as? String else { return }
            switch event {
            case "ready":
                readyTimer?.cancel()
                message.webView?.evaluateJavaScript(parent.widget.setupScript)
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

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            fail()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            fail()
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
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
            if action.navigationType == .linkActivated, let url = action.request.url,
               !FeedbackWidget.isOnServer(url) {
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

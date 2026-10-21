import Network
import SwiftUI
import WebKit

/// Settings ▸ Help's Request a Feature and Contact Support: the Quackback widget at
/// feedback.babybuddy.app, in a sheet.
///
/// A plain WKWebView speaking the widget's `postMessage` protocol, not QuackbackIO/quackback-ios.
/// That package can't open the support conversation (its `OpenView` has no chat), its named
/// `identify` sends an unsigned id and email that the server rejects, and it presents its own
/// full-screen panel with no load-failure signal, so it can't sit in a sheet or fall back to Mail.
///
/// Identity: the widget's anonymous session plus a random per-install ID (`quackback:device`).
/// Nothing else about the user is sent.
enum FeedbackWidget: String, Identifiable {
    case board, support

    var id: Self { self }

    var title: String { self == .board ? "Request a Feature" : "Contact Support" }

    /// The widget view `quackback:open` lands on. Quackback 0.14.1 has no plain Feedback view to
    /// open; `new-post` is the one that lands on the Feedback tab, with "What's your idea?" opened.
    /// `chat` opens Messages, the support thread.
    fileprivate var view: String { self == .board ? "new-post" : "chat" }

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
}

struct FeedbackSheet: View {
    let widget: FeedbackWidget
    /// "Email Support" on the unreachable screen, just before the sheet closes. The caller offers Mail.
    let onEmail: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase = FeedbackWebView.Phase.loading

    var body: some View {
        NavigationStack {
            ZStack {
                BBColor.surface.ignoresSafeArea()
                if phase == .failed {
                    unreachable
                } else {
                    FeedbackWebView(widget: widget, phase: $phase, onClose: { dismiss() })
                        .opacity(phase == .ready ? 1 : 0)
                    if phase == .loading { ProgressView() }
                }
            }
            .navigationTitle(widget.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
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
    let onClose: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let content = WKUserContentController()
        // The widget calls `__quackbackNative.dispatch(event, message)` for ready, close, navigate.
        content.addUserScript(WKUserScript(source: """
            window.__quackbackNative = { dispatch: function (event, message) {
                window.webkit.messageHandlers.quackback.postMessage(
                    { event: event, url: (message && typeof message.url === 'string') ? message.url : '' });
            } };
            """, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        content.addUserScript(WKUserScript(source: """
            var style = document.createElement('style');
            style.textContent = '\(Self.hideCloseButtonCSS)';
            document.head.appendChild(style);
            """, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        content.add(context.coordinator, name: "quackback")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = content

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.load(URLRequest(url: widget.widgetURL, timeoutInterval: 8))
        context.coordinator.startWatching()
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "quackback")
        coordinator.readyTimer?.cancel()
        coordinator.pathMonitor.cancel()
    }

    @MainActor final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        let parent: FeedbackWebView
        var readyTimer: Task<Void, Never>?
        let pathMonitor = NWPathMonitor()

        init(_ parent: FeedbackWebView) { self.parent = parent }

        /// Fails at once when the first network path reading says offline, otherwise after
        /// `readyTimeout` without a `ready`.
        func startWatching() {
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
            case "navigate":
                if let url = URL(string: body["url"] as? String ?? ""), ["https", "http"].contains(url.scheme) {
                    UIApplication.shared.open(url)
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
               url.host != FeedbackWidget.serverURL.host {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        /// `target="_blank"` links.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url { UIApplication.shared.open(url) }
            return nil
        }
    }
}

import Foundation
import WebKit

/// Native sign-in to the Quackback server behind the feedback widget, and the hand-off of its
/// session to the widget's web view (kguydev/feedback-stack#18).
///
/// The calls are the ones Quackback 0.14.1's own portal dialog makes: `portal-signin` mails a
/// 6-digit code, better-auth's `sign-in/email-otp` and `sign-in/email` trade a code or a password
/// for a session, `get-session` says whose it is, and `sign-out` ends it. Nothing here logs the email, the code, the password or
/// the session.
enum FeedbackAuth {
    enum Request {
        case sendCode(email: String)
        case verifyCode(email: String, code: String)
        case password(email: String, password: String)
        case signOut(session: String)
        /// Who the session belongs to, for the Feedback Account row and screen.
        case account(session: String)

        /// For the DEBUG trace: which call, never its values.
        var name: String {
            switch self {
            case .sendCode: "send code"
            case .verifyCode: "verify code"
            case .password: "password"
            case .signOut: "sign out"
            case .account: "get session"
            }
        }

        /// JSON POSTs, except `get-session`, a GET. Sign-out and `get-session` name their session
        /// with a Bearer header, which better-auth's `bearer()` plugin turns back into the cookie.
        func urlRequest(server: URL = FeedbackWidget.serverURL) -> URLRequest {
            let (path, body): (String, [String: String]?) = switch self {
            case .sendCode(let email): ("api/auth/portal-signin", ["email": email, "callbackURL": "/"])
            case .verifyCode(let email, let code): ("api/auth/sign-in/email-otp", ["email": email, "otp": code])
            case .password(let email, let password): ("api/auth/sign-in/email", ["email": email, "password": password])
            case .signOut: ("api/auth/sign-out", [:])
            case .account: ("api/auth/get-session", nil)
            }
            var request = URLRequest(url: server.appending(path: path), timeoutInterval: 15)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            switch self {
            case .signOut(let session), .account(let session):
                request.setValue("Bearer \(session)", forHTTPHeaderField: "Authorization")
            default:
                break
            }
            if let body {
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
            }
            return request
        }
    }

    /// A better-auth session cookie: its value exactly as the server encoded it (the signed
    /// `token.signature`), and when it runs out.
    struct Session: Equatable {
        let value: String
        let expires: Date
    }

    enum Failure: Error, Equatable {
        case wrongCode, wrongPassword
        /// The server's rate limit, and how long it says to wait, when it says.
        case rateLimited(retryAfter: TimeInterval?)
        /// No connection, or the server didn't answer.
        case unreachable
        case other

        var message: String {
            switch self {
            case .wrongCode: String(localized: "That code didn't work. Check the latest email, or send a new code.")
            case .wrongPassword: String(localized: "That email and password don't match.")
            case .rateLimited: String(localized: "Too many tries. Wait a few minutes, then try again.")
            case .unreachable: String(localized: "Can't reach the feedback server.")
            case .other: String(localized: "Something went wrong. Try again in a moment.")
            }
        }
    }

    enum Outcome: Equatable {
        case sent
        case signedIn(Session)
        case failed(Failure)
    }

    /// Read from the response alone, never from the server's error text, which isn't the owner's
    /// voice. A 3xx is a refusal too: Quackback answers a blocked sign-in method or a closed
    /// sign-up with a redirect, which the session below doesn't follow.
    static func outcome(of request: Request, status: Int, headers: [String: String],
                        server: URL = FeedbackWidget.serverURL, now: Date = .now) -> Outcome {
        let header = { (name: String) in headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value }
        if status == 429 {
            let wait = (header("Retry-After") ?? header("X-Retry-After")).flatMap(TimeInterval.init)
            return .failed(.rateLimited(retryAfter: wait))
        }
        switch request {
        case .sendCode, .signOut, .account:
            return (200..<300).contains(status) ? .sent : .failed(.other)
        case .verifyCode, .password:
            if (200..<300).contains(status) {
                // A 200 with no session is a two-factor challenge, which the app doesn't offer.
                return session(fromHeaders: headers, server: server, now: now).map(Outcome.signedIn) ?? .failed(.other)
            }
            if case .verifyCode = request, status == 400 || status == 403 { return .failed(.wrongCode) }
            if case .password = request, status == 401 { return .failed(.wrongPassword) }
            return .failed(.other)
        }
    }

    /// What `get-session` says about a session: its user's email, `null` once the server has
    /// ended it, or nothing usable.
    enum Account: Equatable {
        case signedIn(email: String)
        case ended
        case unknown
    }

    static func account(status: Int, body: Data) -> Account {
        guard status == 200, let json = try? JSONSerialization.jsonObject(with: body, options: .fragmentsAllowed)
        else { return .unknown }
        if json is NSNull { return .ended }
        let email = ((json as? [String: Any])?["user"] as? [String: Any])?["email"] as? String
        return email.map { .signedIn(email: $0) } ?? .unknown
    }

    /// The names the session goes under. better-auth sets the `__Secure-` one over HTTPS, and reads
    /// only that one; official Quackback 0.14.1's `/widget` hands the session to the widget only
    /// when it also finds the plain one. So both, with the same value.
    static let cookieNames = ["__Secure-better-auth.session_token", "better-auth.session_token"]

    /// The session cookie in a sign-in response's `Set-Cookie`, with its expiry (7 days if it
    /// has none).
    static func session(fromHeaders headers: [String: String], server: URL = FeedbackWidget.serverURL,
                        now: Date = .now) -> Session? {
        let cookie = HTTPCookie.cookies(withResponseHeaderFields: headers, for: server)
            .first { cookieNames.contains($0.name) && !$0.value.isEmpty }
        return cookie.map { Session(value: $0.value, expires: $0.expiresDate ?? now.addingTimeInterval(7 * 86_400)) }
    }

    /// The cookies the web view gets, with the attributes better-auth sets: host-only on the
    /// feedback server, path `/`, Secure, HttpOnly, SameSite=Lax.
    static func cookies(for session: Session, server: URL = FeedbackWidget.serverURL) -> [HTTPCookie] {
        cookieNames.compactMap { name in
            HTTPCookie(properties: [
                .name: name,
                .value: session.value,
                .domain: server.host() ?? "",
                .path: "/",
                .secure: "TRUE",
                .expires: session.expires,
                .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax,
                HTTPCookiePropertyKey("HttpOnly"): "TRUE",
            ])
        }
    }
}

// MARK: - The web view's session

/// The feedback session lives only in the web view's cookie store, as it would after a web
/// sign-in: no defaults, no file, no keychain.
@MainActor enum FeedbackSession {
    private static var store: WKHTTPCookieStore { WKWebsiteDataStore.default().httpCookieStore }

    /// Ephemeral, so it neither sends nor keeps cookies of its own, and it doesn't follow
    /// redirects, so a refusal arrives as the 3xx it is.
    private static let urlSession = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }

    static func perform(_ request: FeedbackAuth.Request) async -> FeedbackAuth.Outcome {
        let outcome = await send(request)
        // The call and how it ended, never the values sent or the session.
        feedbackTrace("auth \(request.name): " + {
            switch outcome {
            case .sent: "ok"
            case .signedIn: "signed in"
            case .failed(let failure): "\(failure)"
            }
        }())
        return outcome
    }

    private static func send(_ request: FeedbackAuth.Request) async -> FeedbackAuth.Outcome {
        if FeedbackWidget.isStubbed {
            let (status, headers) = stubResponse(to: request)
            return FeedbackAuth.outcome(of: request, status: status, headers: headers)
        }
        guard let (_, response) = try? await urlSession.data(for: request.urlRequest()),
              let http = response as? HTTPURLResponse
        else { return .failed(.unreachable) }
        let headers = Dictionary(http.allHeaderFields.compactMap { key, value in
            (key as? String).map { ($0, "\(value)") }
        }) { first, _ in first }
        return FeedbackAuth.outcome(of: request, status: http.statusCode, headers: headers)
    }

    /// Both cookie names, written before the widget reloads.
    static func save(_ session: FeedbackAuth.Session) async {
        feedbackTrace("saving session cookies")
        for cookie in FeedbackAuth.cookies(for: session) {
            await store.setCookie(cookie)
            feedbackTrace("saved \(cookie.name)")
        }
    }

    /// Every read of the session waits for the UI-test reset, so a screen that reads it at launch
    /// sees the launch's session, not the last one's or none.
    private static func sessionCookies() async -> [HTTPCookie] {
        await uiTestReset?.value
        return await storedSessionCookies()
    }

    private static func storedSessionCookies() async -> [HTTPCookie] {
        let host = FeedbackWidget.serverURL.host() ?? ""
        // Straight after launch, before WebKit has read its cookies from disk, `allCookies()` comes
        // back empty, which hid a saved session. Fetching the cookie records waits for that read.
        _ = await WKWebsiteDataStore.default().dataRecords(ofTypes: [WKWebsiteDataTypeCookies])
        let all = await store.allCookies()
        let session = all.filter {
            FeedbackAuth.cookieNames.contains($0.name) && ($0.domain == host || $0.domain == "." + host)
        }
        feedbackTrace("cookie store: \(all.count) cookies, \(session.count) session")
        return session
    }

    static var isSignedIn: Bool {
        get async { await !sessionCookies().isEmpty }
    }

    enum Account: Equatable {
        case signedOut
        /// The email is `nil` when the server couldn't be asked.
        case signedIn(email: String?)
    }

    /// Who is signed in, for the Feedback Account row and screen. The email comes from the
    /// server each time, so the app keeps no copy of it; a session the server has ended is
    /// cleared here.
    static func account() async -> Account {
        guard let session = await sessionCookies().first?.value else { return .signedOut }
        var answer = FeedbackAuth.Account.signedIn(email: "parent@example.com")
        if !FeedbackWidget.isStubbed {
            if let (data, response) = try? await urlSession.data(for: FeedbackAuth.Request.account(session: session).urlRequest()),
               let http = response as? HTTPURLResponse {
                answer = FeedbackAuth.account(status: http.statusCode, body: data)
            } else {
                answer = .unknown
            }
        }
        switch answer {
        case .signedIn(let email):
            feedbackTrace("auth get session: signed in")
            return .signedIn(email: email)
        case .ended:
            feedbackTrace("auth get session: ended, clearing the cookies")
            for cookie in await sessionCookies() { await store.deleteCookie(cookie) }
            return .signedOut
        case .unknown:
            feedbackTrace("auth get session: no answer")
            return .signedIn(email: nil)
        }
    }

    /// Clears both cookies, then ends the session on the server. The cookies go whatever the
    /// server says, so the next sheet opens signed out even offline.
    static func signOut() async {
        let cookies = await sessionCookies()
        for cookie in cookies { await store.deleteCookie(cookie) }
        if let value = cookies.first?.value { _ = await perform(.signOut(session: value)) }
    }

    // MARK: UI-test stub

    /// Each UI-test launch starts with no feedback session, or the stub's one under
    /// `BB_FEEDBACK_STUB=signed-in`; cookies otherwise outlive the launch.
    /// `BB_FEEDBACK_KEEP_SESSION=1` keeps the last launch's, for a relaunch test.
    private static var uiTestReset: Task<Void, Never>?

    static func resetForUITests() {
        let environment = ProcessInfo.processInfo.environment
        guard environment["BB_UITEST"] == "1", environment["BB_FEEDBACK_KEEP_SESSION"] != "1" else { return }
        uiTestReset = Task {
            for cookie in await storedSessionCookies() { await store.deleteCookie(cookie) }
            if FeedbackWidget.stubMode == "signed-in" {
                await save(FeedbackAuth.Session(value: "stub.signature", expires: .now.addingTimeInterval(86_400)))
            }
        }
    }

    /// `BB_FEEDBACK_STUB`'s server: an email starting `busy@` hits the rate limit, the code
    /// `000000` and the password `wrong` are refused, and anything else signs in.
    private static func stubResponse(to request: FeedbackAuth.Request) -> (Int, [String: String]) {
        let signedIn = (200, ["Set-Cookie": "__Secure-better-auth.session_token=stub.signature; Max-Age=604800; Path=/; HttpOnly; Secure; SameSite=Lax"])
        switch request {
        case .sendCode(let email): return email.hasPrefix("busy@") ? (429, ["Retry-After": "600"]) : (200, [:])
        case .verifyCode(_, let code): return code == "000000" ? (400, [:]) : signedIn
        case .password(_, let password): return password == "wrong" ? (401, [:]) : signedIn
        case .signOut, .account: return (200, [:])
        }
    }
}

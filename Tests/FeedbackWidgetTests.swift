import XCTest
@testable import BabyBuddy

/// The feedback widget's native sign-in: the calls it makes to Quackback, how it reads the
/// answers, and the session cookies it hands the widget (kguydev/feedback-stack#18).
final class FeedbackWidgetTests: XCTestCase {
    private let server = URL(string: "https://feedback.babybuddy.app")!
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    /// A signed better-auth value, URL-encoded as the server sends it.
    private let signed = "tok123.c2lnbmF0dXJl%2Bpart%3D"

    private func url(_ path: String) -> URL { URL(string: server.absoluteString + path)! }

    private func json(_ request: URLRequest) -> [String: String] {
        (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: String] ?? [:]
    }

    private func outcome(_ request: FeedbackAuth.Request, _ status: Int, _ headers: [String: String] = [:]) -> FeedbackAuth.Outcome {
        FeedbackAuth.outcome(of: request, status: status, headers: headers, server: server, now: now)
    }

    private var signInHeaders: [String: String] {
        ["Set-Cookie": "__Secure-better-auth.session_token=\(signed); Max-Age=604800; Path=/; HttpOnly; Secure; SameSite=Lax",
         "set-auth-token": "tok123.c2lnbmF0dXJl+part="]
    }

    // MARK: Requests

    func testRequestsArePostsOfJSON() {
        let requests: [(FeedbackAuth.Request, String, [String: String])] = [
            (.sendCode(email: "parent@example.com"), "/api/auth/portal-signin",
             ["email": "parent@example.com", "callbackURL": "/"]),
            (.verifyCode(email: "parent@example.com", code: "123456"), "/api/auth/sign-in/email-otp",
             ["email": "parent@example.com", "otp": "123456"]),
            (.password(email: "parent@example.com", password: "hunter22"), "/api/auth/sign-in/email",
             ["email": "parent@example.com", "password": "hunter22"]),
            (.signOut(session: signed), "/api/auth/sign-out", [:]),
        ]
        for (request, path, body) in requests {
            let built = request.urlRequest(server: server)
            XCTAssertEqual(built.url, url(path))
            XCTAssertEqual(built.httpMethod, "POST")
            XCTAssertEqual(built.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(json(built), body, path)
        }
    }

    func testOnlySignOutCarriesTheSession() {
        XCTAssertEqual(FeedbackAuth.Request.signOut(session: signed).urlRequest(server: server)
            .value(forHTTPHeaderField: "Authorization"), "Bearer \(signed)")
        XCTAssertNil(FeedbackAuth.Request.sendCode(email: "a@b.co").urlRequest(server: server)
            .value(forHTTPHeaderField: "Authorization"))
    }

    // MARK: Responses

    func testSendingTheCode() {
        XCTAssertEqual(outcome(.sendCode(email: "a@b.co"), 200), .sent)
        XCTAssertEqual(outcome(.sendCode(email: "a@b.co"), 400), .failed(.other))
        XCTAssertEqual(outcome(.sendCode(email: "a@b.co"), 500), .failed(.other))
    }

    /// The value is copied as sent, still URL-encoded, and expires when `Max-Age` says (from the
    /// real clock: Foundation reads it).
    func testACodeOrPasswordSignsInWithTheCookieAsSent() {
        for call in [FeedbackAuth.Request.verifyCode(email: "a@b.co", code: "123456"), .password(email: "a@b.co", password: "x")] {
            guard case .signedIn(let session) = outcome(call, 200, signInHeaders) else { return XCTFail("\(call.name)") }
            XCTAssertEqual(session.value, signed)
            XCTAssertEqual(session.expires.timeIntervalSinceNow, 604_800, accuracy: 60)
        }
    }

    /// Without `__Secure-` (a server on plain HTTP) the plain name is the session too.
    func testThePlainCookieNameCounts() {
        let headers = ["Set-Cookie": "better-auth.session_token=\(signed); Path=/; HttpOnly; SameSite=Lax"]
        XCTAssertEqual(outcome(.verifyCode(email: "a@b.co", code: "123456"), 200, headers),
                       .signedIn(FeedbackAuth.Session(value: signed, expires: now.addingTimeInterval(7 * 86_400))))
    }

    /// A 200 with no session cookie is a two-factor challenge, which the app doesn't offer.
    func testSuccessWithoutASessionIsAFailure() {
        let other = ["Set-Cookie": "qb.device=abc; Path=/"]
        XCTAssertEqual(outcome(.password(email: "a@b.co", password: "x"), 200, other), .failed(.other))
        XCTAssertEqual(outcome(.verifyCode(email: "a@b.co", code: "123456"), 200), .failed(.other))
    }

    /// Wrong, expired, and locked after three tries all mean "send a new code".
    func testRefusedCodes() {
        for status in [400, 403] {
            XCTAssertEqual(outcome(.verifyCode(email: "a@b.co", code: "000000"), status), .failed(.wrongCode))
        }
    }

    func testWrongPassword() {
        XCTAssertEqual(outcome(.password(email: "a@b.co", password: "x"), 401), .failed(.wrongPassword))
    }

    /// Quackback refuses a blocked sign-in method or a closed sign-up with a redirect.
    func testRedirectsAreRefusals() {
        let refusal = ["Location": "/?auth=signin&error=signup_not_allowed"]
        XCTAssertEqual(outcome(.verifyCode(email: "a@b.co", code: "123456"), 302, refusal), .failed(.other))
        XCTAssertEqual(outcome(.password(email: "a@b.co", password: "x"), 302, refusal), .failed(.other))
    }

    /// Quackback's limiter says `Retry-After`, better-auth's `X-Retry-After`, either may say nothing.
    func testRateLimits() {
        let calls: [FeedbackAuth.Request] = [.sendCode(email: "a@b.co"), .verifyCode(email: "a@b.co", code: "123456"),
                                             .password(email: "a@b.co", password: "x")]
        for call in calls {
            XCTAssertEqual(outcome(call, 429, ["Retry-After": "600"]), .failed(.rateLimited(retryAfter: 600)))
            XCTAssertEqual(outcome(call, 429, ["x-retry-after": "8"]), .failed(.rateLimited(retryAfter: 8)))
            XCTAssertEqual(outcome(call, 429), .failed(.rateLimited(retryAfter: nil)))
        }
    }

    func testMessagesAreTheOwnersWords() {
        XCTAssertEqual(FeedbackAuth.Failure.wrongCode.message,
                       "That code didn't work. Check the latest email, or send a new code.")
        XCTAssertEqual(FeedbackAuth.Failure.rateLimited(retryAfter: 60).message,
                       "Too many tries. Wait a few minutes, then try again.")
        XCTAssertEqual(FeedbackAuth.Failure.wrongPassword.message, "That email and password don't match.")
    }

    // MARK: Cookies

    /// Both names, the value as the server encoded it, and better-auth's attributes, so official
    /// Quackback's widget (plain name) and its session read (`__Secure-` name) both find it.
    func testTheWidgetGetsBothCookies() throws {
        let expires = now.addingTimeInterval(604_800)
        let cookies = FeedbackAuth.cookies(for: FeedbackAuth.Session(value: signed, expires: expires), server: server)
        XCTAssertEqual(cookies.map(\.name), ["__Secure-better-auth.session_token", "better-auth.session_token"])
        for cookie in cookies {
            XCTAssertEqual(cookie.value, signed)
            XCTAssertEqual(cookie.domain, "feedback.babybuddy.app")
            XCTAssertEqual(cookie.path, "/")
            XCTAssertTrue(cookie.isSecure)
            XCTAssertTrue(cookie.isHTTPOnly)
            XCTAssertEqual(cookie.sameSitePolicy, .sameSiteLax)
            XCTAssertEqual(try XCTUnwrap(cookie.expiresDate).timeIntervalSince1970, expires.timeIntervalSince1970, accuracy: 1)
        }
    }

    // MARK: Widget links

    /// A widget link to Quackback's sign-in opens the native one instead.
    func testSignInPages() {
        for path in ["/auth/login", "/auth/login?callbackUrl=/widget", "/?auth=signin", "/?auth=signup"] {
            XCTAssertTrue(FeedbackWidget.isSignInURL(url(path)), path)
        }
        for path in ["/", "/b/feature-requests", "/widget?source=native", "/authors"] {
            XCTAssertFalse(FeedbackWidget.isSignInURL(url(path)), path)
        }
        XCTAssertFalse(FeedbackWidget.isSignInURL(URL(string: "https://github.com/auth/login")!))
    }
}

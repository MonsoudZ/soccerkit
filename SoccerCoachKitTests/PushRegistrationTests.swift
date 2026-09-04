import XCTest
@testable import SoccerCoachKit

/// The device-token half of push notifications.
///
/// The interesting part is not the request but the ordering: a device token arrives from
/// APNs and a session arrives from Sign in with Apple, in either order and often an app
/// launch apart, and neither can register on its own. Everything below is about what
/// happens when only one of them is in hand.
@MainActor
final class PushRegistrationTests: XCTestCase {
    private let deviceToken = Data([0xaa, 0x11, 0xbb, 0x22])

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    private func makeRegistrar(session token: String?) -> (PushRegistrar, UserDefaults) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: config)
        let defaults = UserDefaults(suiteName: "push-tests-\(UUID().uuidString)")!
        let registrar = PushRegistrar(
            makeClient: { provider in
                APIClient(baseURL: URL(string: "http://backend.test")!,
                          session: urlSession, tokenProvider: provider)
            },
            sessionToken: { token },
            defaults: defaults,
            isConfigured: { true }
        )
        return (registrar, defaults)
    }

    /// Waits for the registrar's detached request to land, since registration is
    /// deliberately fire-and-forget: nothing in the app waits on it.
    private func waitForRequest(_ predicate: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && !predicate() {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
    }

    func testDeviceTokenIsSentAsLowercaseHex() {
        XCTAssertEqual(PushRegistrar.hex(Data([0x00, 0x0f, 0xa0, 0xff])), "000fa0ff")
    }

    /// With both halves in hand, the token is registered — bearer, path and body.
    func testRegistersWhenTokenAndSessionAreBothPresent() {
        let (registrar, _) = makeRegistrar(session: "session-abc")
        var seenBearer: String?
        var seenBody: Data?
        StubURLProtocol.responder = { request in
            seenBearer = request.value(forHTTPHeaderField: "Authorization")
            seenBody = StubURLProtocol.body(of: request)
            return (200, Data("{}".utf8))
        }

        registrar.deviceTokenReceived(deviceToken)
        waitForRequest { StubURLProtocol.seenPaths.contains("/v1/me/devices") }

        XCTAssertTrue(StubURLProtocol.seenPaths.contains("/v1/me/devices"),
                      "expected a registration, saw \(StubURLProtocol.seenPaths)")
        XCTAssertEqual(seenBearer, "Bearer session-abc")
        let body = try? JSONDecoder().decode(RegisterDeviceRequest.self, from: seenBody ?? Data())
        XCTAssertEqual(body?.token, "aa11bb22")
        XCTAssertEqual(body?.platform, "ios")
    }

    /// A token with no session yet is kept, not dropped. This is the ordering that
    /// actually happens on a returning coach's launch, and losing the token here would
    /// leave them unreachable until iOS next chose to issue one.
    func testTokenWithoutASessionIsRememberedAndSentLater() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: config)
        let defaults = UserDefaults(suiteName: "push-tests-\(UUID().uuidString)")!
        var session: String?
        let registrar = PushRegistrar(
            makeClient: { provider in
                APIClient(baseURL: URL(string: "http://backend.test")!,
                          session: urlSession, tokenProvider: provider)
            },
            sessionToken: { session },
            defaults: defaults,
            isConfigured: { true }
        )
        StubURLProtocol.responder = { _ in (200, Data("{}".utf8)) }

        registrar.deviceTokenReceived(deviceToken)
        XCTAssertTrue(StubURLProtocol.seenPaths.isEmpty,
                      "nothing to register against yet, saw \(StubURLProtocol.seenPaths)")
        XCTAssertEqual(registrar.deviceToken, "aa11bb22", "the token must be kept for later")

        // Sign-in completes; the second half arrives.
        session = "session-later"
        registrar.registerIfPossible()
        waitForRequest { StubURLProtocol.seenPaths.contains("/v1/me/devices") }
        XCTAssertTrue(StubURLProtocol.seenPaths.contains("/v1/me/devices"),
                      "the stored token should register once a session exists")
    }

    /// Registering is idempotent on the server, but the several things that can trigger
    /// it should not each re-send the same pair.
    func testRepeatedTriggersSendOnce() {
        let (registrar, _) = makeRegistrar(session: "session-abc")
        StubURLProtocol.responder = { _ in (200, Data("{}".utf8)) }

        registrar.deviceTokenReceived(deviceToken)
        waitForRequest { !StubURLProtocol.seenPaths.isEmpty }
        registrar.registerIfPossible()
        registrar.registerIfPossible()
        waitForRequest { StubURLProtocol.seenPaths.count > 1 }

        XCTAssertEqual(StubURLProtocol.seenPaths.filter { $0 == "/v1/me/devices" }.count, 1,
                       "saw \(StubURLProtocol.seenPaths)")
    }

    /// Sign-out has to reach the server while the credential still works, and the
    /// session is cleared the instant `willSignOut` returns.
    ///
    /// So the session is torn down here immediately after the call, exactly as
    /// `AuthController.signOut` does. That is the point of the test: the request runs in
    /// a detached task, and a registrar that read the token from storage inside that
    /// task would find nothing and send the DELETE unauthenticated. Capturing it up
    /// front is what makes the bearer below survive.
    func testUnregisterUsesTheSessionBeingTornDown() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: config)
        var session: String? = "about-to-go"
        let registrar = PushRegistrar(
            makeClient: { provider in
                APIClient(baseURL: URL(string: "http://backend.test")!,
                          session: urlSession, tokenProvider: provider)
            },
            sessionToken: { session },
            defaults: UserDefaults(suiteName: "push-tests-\(UUID().uuidString)")!,
            isConfigured: { true }
        )
        var seenMethod: String?
        var seenBearer: String?
        StubURLProtocol.responder = { request in
            seenMethod = request.httpMethod
            seenBearer = request.value(forHTTPHeaderField: "Authorization")
            return (200, Data("{}".utf8))
        }
        registrar.deviceTokenReceived(deviceToken)
        waitForRequest { !StubURLProtocol.seenPaths.isEmpty }
        StubURLProtocol.seenPaths = []

        registrar.unregisterCurrentDevice()
        // What AuthController.signOut does on the very next line.
        session = nil
        waitForRequest { StubURLProtocol.seenPaths.contains("/v1/me/devices/aa11bb22") }

        XCTAssertTrue(StubURLProtocol.seenPaths.contains("/v1/me/devices/aa11bb22"),
                      "saw \(StubURLProtocol.seenPaths)")
        XCTAssertEqual(seenMethod, "DELETE")
        XCTAssertEqual(seenBearer, "Bearer about-to-go",
                       "the DELETE must carry the session being torn down, not whatever is left after")
    }

    /// A CloudKit-only build has no server to tell, and must not ask iOS for a token or
    /// make a call. The rest of this layer holds the same rule.
    func testUnconfiguredBuildDoesNothing() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: config)
        let registrar = PushRegistrar(
            makeClient: { provider in
                APIClient(baseURL: URL(string: "http://backend.test")!,
                          session: urlSession, tokenProvider: provider)
            },
            sessionToken: { "session-abc" },
            defaults: UserDefaults(suiteName: "push-tests-\(UUID().uuidString)")!,
            isConfigured: { false }
        )
        StubURLProtocol.responder = { _ in (200, Data("{}".utf8)) }

        registrar.deviceTokenReceived(deviceToken)
        registrar.registerIfPossible()
        registrar.unregisterCurrentDevice()
        waitForRequest { !StubURLProtocol.seenPaths.isEmpty }

        XCTAssertTrue(StubURLProtocol.seenPaths.isEmpty,
                      "an unconfigured build called the backend: \(StubURLProtocol.seenPaths)")
    }
}

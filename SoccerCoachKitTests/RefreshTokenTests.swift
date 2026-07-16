import XCTest
@testable import SoccerCoachKit

/// Scripts HTTP responses by (method, path, bearer) so a test can drive the real
/// APIClient/APISyncService stack — including a 401 that triggers a token refresh
/// and a retry.
final class StubURLProtocol: URLProtocol {
    struct Route { let method: String; let path: String; let bearer: String? }
    /// (status, jsonBody) keyed by a matcher the test installs.
    static var responder: ((URLRequest) -> (Int, Data))?
    static var seenPaths: [String] = []

    static func reset() { responder = nil; seenPaths = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        Self.seenPaths.append(request.url?.path ?? "")
        let (status, body) = Self.responder?(request) ?? (500, Data())
        let response = HTTPURLResponse(url: request.url!, statusCode: status,
                                       httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor
final class RefreshTokenTests: XCTestCase {
    private func bearer(_ r: URLRequest) -> String? {
        r.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
    }

    private func makeStack() -> (APISyncService, TokenStore, UserDefaults) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let defaults = UserDefaults(suiteName: "refresh-tests-\(UUID().uuidString)")!
        let tokens = TokenStore(storage: InMemoryTokenStorage())
        let client = APIClient(baseURL: URL(string: "http://backend.test")!,
                               session: session, tokenProvider: { tokens.token })
        let service = APISyncService(client: client, namespace: "test",
                                     defaults: defaults, tokenStore: tokens)
        return (service, tokens, defaults)
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    /// The Apple sign-in response now carries a refresh token; the client must
    /// decode it (older builds dropped it, so it was lost).
    func testAppleAuthResponseDecodesRefreshToken() throws {
        let json = Data(#"{"token":"access","refreshToken":"refresh","personID":"p1"}"#.utf8)
        let resp = try JSONDecoder().decode(AuthResponse.self, from: json)
        XCTAssertEqual(resp.token, "access")
        XCTAssertEqual(resp.refreshToken, "refresh")
    }

    /// The core fix: an expired access token no longer dead-ends sync. A 401 on a
    /// sync call rotates the token via /v1/auth/refresh and retries, and the new
    /// tokens are persisted (the endpoint rotates the refresh token too).
    func testExpiredTokenIsRefreshedAndRetried() {
        let (service, tokens, _) = makeStack()
        tokens.token = "expired"
        tokens.refreshToken = "refresh-1"

        StubURLProtocol.responder = { [bearer] req in
            let path = req.url?.path ?? ""
            switch (req.httpMethod ?? "", path) {
            case ("POST", "/v1/auth/refresh"):
                return (200, Data(#"{"accessToken":"fresh","refreshToken":"refresh-2"}"#.utf8))
            case ("GET", "/v1/sync"):
                return bearer(req) == "fresh"
                    ? (200, Data(#"{"records":[],"deletes":[],"cursor":"9"}"#.utf8))
                    : (401, Data()) // the "expired" token
            default:
                return (500, Data())
            }
        }

        let synced = expectation(description: "sync succeeds after refresh")
        service.onStatusChange = { status in
            if case .synced = status { synced.fulfill() }
            if case .failed(let m) = status { XCTFail("unexpected failure: \(m)") }
        }
        service.start()
        wait(for: [synced], timeout: 5)

        XCTAssertEqual(tokens.token, "fresh", "rotated access token must be stored")
        XCTAssertEqual(tokens.refreshToken, "refresh-2", "rotated refresh token must be stored")
        XCTAssertTrue(StubURLProtocol.seenPaths.contains("/v1/auth/refresh"), "a refresh must have been attempted")
    }

    /// When the refresh token itself is rejected (truly expired / revoked), the
    /// session is dead: surface the failure and clear the tokens so the next call
    /// fails fast to "sign in again" rather than looping on a dead token.
    func testRejectedRefreshClearsTheSession() {
        let (service, tokens, _) = makeStack()
        tokens.token = "expired"
        tokens.refreshToken = "refresh-stale"

        StubURLProtocol.responder = { req in
            (req.url?.path == "/v1/auth/refresh") ? (401, Data()) : (401, Data())
        }

        let failed = expectation(description: "sync fails when refresh is rejected")
        service.onStatusChange = { status in
            if case .failed = status { failed.fulfill() }
        }
        service.start()
        wait(for: [failed], timeout: 5)

        XCTAssertNil(tokens.token, "a dead session must clear the access token")
        XCTAssertNil(tokens.refreshToken, "a dead session must clear the refresh token")
    }
}

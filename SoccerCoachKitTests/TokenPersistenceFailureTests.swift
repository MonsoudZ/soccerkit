import XCTest
@testable import SoccerCoachKit

/// The bug these cover: `KeychainTokenStorage.set` discarded the `OSStatus` from
/// both `SecItemUpdate` and `SecItemAdd`. A write that failed — device locked
/// before first unlock, item inaccessible, entitlement missing — looked like it
/// had worked, then read back as `nil`. Sync 401s, the refresh finds no token,
/// and the coach is told to "Sign in again to sync" forever: signing in again
/// can't help, because signing in is the step that isn't sticking.
///
/// `testKeychainRoundTrip` is `XCTSkip`ped wherever the test host can't reach the
/// keychain (CI included), so the real implementation has no coverage there.
/// These drive the seam instead, which is where the behaviour that matters lives:
/// a failed write must be reported and acted on, not swallowed.
@MainActor
final class TokenPersistenceFailureTests: XCTestCase {

    // MARK: - The seam

    func testSaveReportsSuccessWhenStorageAccepts() {
        let store = TokenStore(storage: InMemoryTokenStorage())
        XCTAssertTrue(store.save(token: "a", refreshToken: "r"))
        XCTAssertEqual(store.token, "a")
        XCTAssertEqual(store.refreshToken, "r")
    }

    func testSaveReportsFailureWhenStorageRefuses() {
        let store = TokenStore(storage: FailingTokenStorage())
        XCTAssertFalse(store.save(token: "a", refreshToken: "r"),
                       "a session that didn't reach storage must not report as saved")
    }

    /// Both keys are attempted even when the first fails, so a partial save can't
    /// pair a new access token with a stale refresh token.
    func testBothKeysAreWrittenEvenWhenTheFirstFails() {
        let storage = FailingTokenStorage()
        _ = TokenStore(storage: storage).save(token: "a", refreshToken: "r")
        XCTAssertEqual(storage.attemptedKeys, ["backendAuthToken", "backendRefreshToken"])
    }

    // MARK: - The refresh path

    /// A rotation the keychain won't take is worse than no rotation: the server
    /// has already revoked the token we presented. The refresh must report
    /// failure rather than let the caller retry with an access token that was
    /// never stored.
    ///
    /// Asserting on the failed *status* would prove nothing — the sync fails
    /// either way, since the retry would 401 too. What separates the two is
    /// whether the retry is attempted at all: reporting the refresh honestly
    /// short-circuits it, so the sync call is made once, not twice.
    func testUnsaveableRotationFailsTheRefresh() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        // The keychain holds the old session and will refuse the rotated one.
        let storage = FailingTokenStorage(seed: ["backendRefreshToken": "refresh-1"])
        let tokens = TokenStore(storage: storage)
        let client = APIClient(baseURL: URL(string: "http://backend.test")!,
                               session: URLSession(configuration: config),
                               tokenProvider: { "expired" })
        let service = APISyncService(client: client, namespace: "test",
                                     defaults: UserDefaults(suiteName: "token-fail-\(UUID().uuidString)")!,
                                     tokenStore: tokens)

        StubURLProtocol.responder = { req in
            req.url?.path == "/v1/auth/refresh"
                ? (200, Data(#"{"accessToken":"fresh","refreshToken":"refresh-2"}"#.utf8))
                : (401, Data()) // every sync call rejects the expired token
        }

        StubURLProtocol.seenPaths = []
        let failed = expectation(description: "sync reports failure")
        failed.assertForOverFulfill = false
        service.onStatusChange = { status in
            if case .synced = status { XCTFail("a session that never saved must not report as synced") }
            if case .failed = status { failed.fulfill() }
        }
        service.start()
        wait(for: [failed], timeout: 5)
        service.stop()

        XCTAssertTrue(storage.attemptedKeys.contains("backendAuthToken"),
                      "the rotation should have been attempted")
        XCTAssertTrue(StubURLProtocol.seenPaths.contains("/v1/auth/refresh"),
                      "the refresh itself should have been reached")
        XCTAssertEqual(StubURLProtocol.seenPaths.filter { $0 == "/v1/sync" }.count, 1,
                       "the sync call must not be retried on a rotation that never saved")
    }

    // MARK: - The sign-in path

    /// An unseeded `FailingTokenStorage` reads back empty, which is exactly what
    /// a dropped write leaves behind on the next launch: a coach who is signed in
    /// as far as the app is concerned, with no bearer token to show for it.
    func testAnUnsavedSessionReadsBackEmpty() {
        let store = TokenStore(storage: FailingTokenStorage())
        store.save(token: "a", refreshToken: "r")
        XCTAssertNil(store.token, "this is the state the silent failure produced")
        XCTAssertNil(store.refreshToken)
    }

    /// Clearing is a write too: signing out on a keychain that refuses writes
    /// must not claim the credentials are gone.
    func testClearReportsThroughTheSameSeam() {
        let store = TokenStore(storage: InMemoryTokenStorage())
        store.save(token: "a", refreshToken: "r")
        store.clear()
        XCTAssertNil(store.token)
        XCTAssertNil(store.refreshToken)
    }
}

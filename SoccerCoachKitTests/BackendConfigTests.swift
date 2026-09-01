import XCTest
@testable import SoccerCoachKit

/// Confirms the backend layer is inert until configured — the guarantee that
/// wiring `APISyncService` into `storedOrSample` doesn't disturb the shipping
/// CloudKit path.
///
/// These drive an injected info dictionary rather than `Bundle.main`. Reading the
/// live bundle made them assertions about how the running build was configured,
/// not about the code: `Config/Local.xcconfig` is gitignored and the README tells
/// every developer to create one, so the moment you set up local backend work the
/// suite went red — while CI, which has no such file, stayed green.
final class BackendConfigTests: XCTestCase {

    // MARK: - Resolution rules

    func testNoKeyMeansUnconfigured() {
        XCTAssertNil(BackendConfig.baseURL(in: StubInfoDictionary.unconfigured))
        XCTAssertFalse(BackendConfig.isConfigured(in: StubInfoDictionary.unconfigured))
    }

    /// The shipping case: `Config/Backend.xcconfig` leaves `BACKEND_BASE_URL`
    /// unset, and `$(BACKEND_BASE_URL)` expands to an empty string in the plist —
    /// present as a key, but not a backend.
    func testEmptyValueMeansUnconfigured() {
        XCTAssertNil(BackendConfig.baseURL(in: StubInfoDictionary.empty))
        XCTAssertFalse(BackendConfig.isConfigured(in: StubInfoDictionary.empty))
    }

    func testWhitespaceOnlyValueMeansUnconfigured() {
        let info = StubInfoDictionary([BackendConfig.baseURLKey: "   "])
        XCTAssertNil(BackendConfig.baseURL(in: info))
    }

    func testNonStringValueMeansUnconfigured() {
        let info = StubInfoDictionary([BackendConfig.baseURLKey: 42])
        XCTAssertNil(BackendConfig.baseURL(in: info))
    }

    func testConfiguredValueResolves() {
        let info = StubInfoDictionary([BackendConfig.baseURLKey: "http://127.0.0.1:3000/api"])
        XCTAssertTrue(BackendConfig.isConfigured(in: info))
        XCTAssertEqual(BackendConfig.baseURL(in: info)?.absoluteString, "http://127.0.0.1:3000/api")
    }

    // MARK: - Client construction

    func testAPIClientFailsToInitWithoutBackend() {
        XCTAssertNil(APIClient(info: StubInfoDictionary.unconfigured, tokenProvider: { nil }),
                     "no base URL → no client")
        XCTAssertNil(APIClient(info: StubInfoDictionary.empty, tokenProvider: { nil }),
                     "an empty BackendBaseURL is not a backend")
    }

    func testAPIClientBuildsFromAConfiguredInfoDictionary() {
        let info = StubInfoDictionary([BackendConfig.baseURLKey: "http://localhost:8080"])
        let client = APIClient(info: info, tokenProvider: { "jwt" })
        XCTAssertEqual(client?.baseURL.absoluteString, "http://localhost:8080")
    }

    func testAPIClientBuildsWithExplicitBaseURL() {
        let client = APIClient(baseURL: URL(string: "http://localhost:8080")!, tokenProvider: { "jwt" })
        XCTAssertEqual(client.baseURL.absoluteString, "http://localhost:8080")
    }

    @MainActor
    func testAPISyncServiceSatisfiesTheRemoteSyncSeam() {
        // Compile-time proof that the API service is a drop-in for the same seam
        // AppStore drives CloudKit through.
        let client = APIClient(baseURL: URL(string: "http://localhost:8080")!, tokenProvider: { nil })
        let service: RemoteSyncService = APISyncService(client: client, namespace: "test")
        service.onStatusChange = { _ in }
        XCTAssertNotNil(service.onStatusChange)
    }
}

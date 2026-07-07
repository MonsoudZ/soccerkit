import XCTest
@testable import SoccerCoachKit

/// Confirms the backend layer is inert until configured — the guarantee that
/// wiring `APISyncService` into `storedOrSample` doesn't disturb the shipping
/// CloudKit path.
final class BackendConfigTests: XCTestCase {

    func testBackendUnconfiguredByDefault() {
        // The test host's generated Info.plist has no BackendBaseURL, so the
        // whole API path stays off and the app runs on CloudKit + local.
        XCTAssertFalse(BackendConfig.isConfigured)
        XCTAssertNil(BackendConfig.baseURL)
    }

    func testAPIClientFailsToInitWithoutBackend() {
        XCTAssertNil(APIClient(tokenProvider: { nil }), "no base URL → no client")
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

import XCTest
@testable import SoccerCoachKit

/// The gap these cover: `APISyncService.pull()` fired only from `start()` and
/// `setNamespace`, so once the app was running it never asked the server for
/// anything again. A coach editing on their iPad saw nothing of it on their
/// phone until the phone was relaunched — and an app that stays in the
/// background for days is not relaunched often.
///
/// The app now refreshes when it returns to the foreground, which is when a
/// coach is actually looking.
@MainActor
final class RemoteRefreshTests: XCTestCase {

    private let timeout: TimeInterval = 20

    // MARK: - The store's side

    func testRefreshFromRemoteAsksTheService() {
        UserDefaults.standard.set(true, forKey: "iCloudSyncEnabled")
        let mock = MockRemoteSync()
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 1),
                             persistence: InMemoryPersistence(), remoteSync: mock)
        store.cloudSyncEnabled = true
        let before = mock.refreshCount

        store.refreshFromRemote()

        XCTAssertEqual(mock.refreshCount, before + 1)
    }

    /// A coach who turned sync off shouldn't have the app quietly reaching for
    /// the network every time they open it.
    func testRefreshFromRemoteIsANoOpWhenSyncIsOff() {
        let mock = MockRemoteSync()
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 1),
                             persistence: InMemoryPersistence(), remoteSync: mock)
        store.cloudSyncEnabled = false
        let before = mock.refreshCount

        store.refreshFromRemote()

        XCTAssertEqual(mock.refreshCount, before, "sync is off; nothing should be fetched")
    }

    // MARK: - The service's side

    private func makeService() -> APISyncService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let tokens = TokenStore(storage: InMemoryTokenStorage())
        tokens.token = "access"
        let client = APIClient(baseURL: URL(string: "http://backend.test")!,
                               session: URLSession(configuration: config),
                               tokenProvider: { tokens.token })
        return APISyncService(client: client, namespace: "test",
                              defaults: UserDefaults(suiteName: "refresh-\(UUID().uuidString)")!,
                              tokenStore: tokens)
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    /// A refresh actually goes to the network — the second pull is the point.
    func testRefreshPullsAgain() {
        let service = makeService()
        service.snapshotProvider = { TestData.snapshot(playerCount: 1) }

        let firstPull = expectation(description: "the launch pull")
        firstPull.assertForOverFulfill = false
        StubURLProtocol.responder = { req in
            if req.httpMethod == "GET" { firstPull.fulfill() }
            return req.httpMethod == "GET"
                ? (200, Data(#"{"records":[],"deletes":[],"cursor":"1"}"#.utf8))
                : (200, Data(#"{"conflicts":[],"cursor":"1"}"#.utf8))
        }
        service.start()
        wait(for: [firstPull], timeout: timeout)

        let pullsBefore = StubURLProtocol.seenPaths.filter { $0 == "/v1/sync" }.count
        let secondPull = expectation(description: "the foreground refresh")
        secondPull.assertForOverFulfill = false
        StubURLProtocol.responder = { req in
            if req.httpMethod == "GET" { secondPull.fulfill() }
            return (200, Data(#"{"records":[],"deletes":[],"cursor":"2"}"#.utf8))
        }

        service.refresh()
        wait(for: [secondPull], timeout: timeout)
        service.stop()

        XCTAssertGreaterThan(StubURLProtocol.seenPaths.filter { $0 == "/v1/sync" }.count, pullsBefore,
                             "refresh must issue another request, not reuse the launch pull")
    }

    /// Nothing to pull with while stopped, so the refresh must stay off the
    /// network rather than 401 its way to a failure banner.
    func testRefreshDoesNothingWhileStopped() {
        let service = makeService()
        StubURLProtocol.responder = { _ in (200, Data(#"{"records":[],"deletes":[],"cursor":"1"}"#.utf8)) }
        StubURLProtocol.seenPaths = []

        service.refresh() // never started

        XCTAssertTrue(StubURLProtocol.seenPaths.isEmpty, "a stopped service must not reach the network")
    }

    /// A refresh applies what the server sends, so the other device's edit lands
    /// in the store rather than merely being fetched.
    func testRefreshAppliesFetchedRecords() throws {
        let service = makeService()
        let team = TestData.team()
        let record = try XCTUnwrap(SyncRecords.records(from: TestData.snapshot(playerCount: 1))
            .first { $0.type == .team })
        let dto = try SyncWireCodec.dto(from: SyncRecord(type: .team, id: team.id.uuidString,
                                                         payload: record.payload))
        let body = try JSONEncoder().encode(SyncPullResponse(records: [dto], deletes: [], cursor: "2"))

        var applied: [SyncRecord] = []
        let got = expectation(description: "records reach the store")
        got.assertForOverFulfill = false
        service.applyRemoteChanges = { upserts, _ in
            applied += upserts
            got.fulfill()
        }
        StubURLProtocol.responder = { _ in (200, body) }
        service.start()
        wait(for: [got], timeout: timeout)
        service.stop()

        XCTAssertFalse(applied.isEmpty, "a pull that returns records must hand them to the store")
    }
}

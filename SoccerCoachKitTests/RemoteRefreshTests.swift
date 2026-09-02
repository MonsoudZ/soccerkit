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

    func testRefreshFromRemoteAsksTheService() async {
        UserDefaults.standard.set(true, forKey: "iCloudSyncEnabled")
        let mock = MockRemoteSync()
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 1),
                             persistence: InMemoryPersistence(), remoteSync: mock)
        store.cloudSyncEnabled = true
        let before = mock.refreshCount

        await store.refreshFromRemote()

        XCTAssertEqual(mock.refreshCount, before + 1)
    }

    /// A coach who turned sync off shouldn't have the app quietly reaching for
    /// the network every time they open it.
    func testRefreshFromRemoteIsANoOpWhenSyncIsOff() async {
        let mock = MockRemoteSync()
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 1),
                             persistence: InMemoryPersistence(), remoteSync: mock)
        store.cloudSyncEnabled = false
        let before = mock.refreshCount

        await store.refreshFromRemote()

        XCTAssertEqual(mock.refreshCount, before, "sync is off; nothing should be fetched")
    }

    /// The spinner is held for exactly as long as the fetch. Returning early
    /// would drop it the instant the gesture ended, which reads as "refreshed,
    /// nothing new" whatever the network was really doing.
    func testRefreshWaitsForTheFetchToSettle() async {
        UserDefaults.standard.set(true, forKey: "iCloudSyncEnabled")
        let mock = MockRemoteSync()
        mock.holdsRefreshCompletion = true
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 1),
                             persistence: InMemoryPersistence(), remoteSync: mock)
        store.cloudSyncEnabled = true

        var returned = false
        let call = Task { await store.refreshFromRemote(); returned = true }
        for _ in 0..<200 where mock.refreshCount == 0 { await Task.yield() }

        XCTAssertEqual(mock.refreshCount, 1)
        XCTAssertFalse(returned, "the call must still be waiting on the fetch")

        mock.finishRefresh()
        await call.value
        XCTAssertTrue(returned, "and must return once the fetch settles")
    }

    /// An unconfigured build has no remote at all. The gesture must fall
    /// through rather than sit on a continuation nothing will ever resume --
    /// this test hangs until its timeout if that regresses.
    func testRefreshWithNoRemoteReturnsImmediately() async {
        UserDefaults.standard.set(true, forKey: "iCloudSyncEnabled")
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 1),
                             persistence: InMemoryPersistence())
        store.cloudSyncEnabled = true

        await store.refreshFromRemote()
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
    ///
    /// It waits for the launch pull to *settle* before refreshing, not merely
    /// for its request to appear: a refresh issued mid-pull now joins that pull
    /// rather than racing it, so refreshing too early would prove nothing about
    /// whether a refresh can fetch at all.
    func testRefreshPullsAgain() {
        let service = makeService()
        service.snapshotProvider = { TestData.snapshot(playerCount: 1) }

        StubURLProtocol.responder = { req in
            req.httpMethod == "GET"
                ? (200, Data(#"{"records":[],"deletes":[],"cursor":"1"}"#.utf8))
                : (200, Data(#"{"conflicts":[],"cursor":"1"}"#.utf8))
        }
        let launched = expectation(description: "the launch pull settled")
        launched.assertForOverFulfill = false
        service.onStatusChange = { if case .synced = $0 { launched.fulfill() } }
        service.start()
        wait(for: [launched], timeout: timeout)

        let pullsBefore = Self.pullCount
        StubURLProtocol.responder = { _ in
            (200, Data(#"{"records":[],"deletes":[],"cursor":"2"}"#.utf8))
        }

        let refreshed = expectation(description: "the foreground refresh settled")
        service.refresh { refreshed.fulfill() }
        wait(for: [refreshed], timeout: timeout)
        service.stop()

        XCTAssertGreaterThan(Self.pullCount, pullsBefore,
                             "refresh must issue another request, not reuse the launch pull")
    }

    /// A stopped service does no work, but a caller holding a spinner is still
    /// waiting on the completion. One that never comes is a spinner that never
    /// stops.
    func testAStoppedRefreshStillReportsSettled() {
        let service = makeService()
        var settled = false

        service.refresh { settled = true }

        XCTAssertTrue(settled, "every path must report back, including the one that declines to work")
    }

    /// Two refreshes landing together must share one fetch rather than race
    /// over the cursor: both would read the same `since`, fetch the same page,
    /// and the "cursor stood still" guard that ends the drain would read one
    /// pull's write as the other's answer. Pull-to-refresh turns that from a
    /// launch-timing accident into something a coach can do on purpose.
    func testConcurrentRefreshesShareOneFetch() async {
        let service = makeService()
        service.snapshotProvider = { TestData.snapshot(playerCount: 1) }

        // Holds the server's answer open so the pull is demonstrably still in
        // flight when the refreshes arrive.
        let held = DispatchSemaphore(value: 0)
        StubURLProtocol.responder = { req in
            if req.httpMethod == "GET" { held.wait() }
            return req.httpMethod == "GET"
                ? (200, Data(#"{"records":[],"deletes":[],"cursor":"1"}"#.utf8))
                : (200, Data(#"{"conflicts":[],"cursor":"1"}"#.utf8))
        }

        service.start()
        await spin(until: { Self.pullCount == 1 })

        var settled = 0
        service.refresh { settled += 1 }
        service.refresh { settled += 1 }
        for _ in 0..<200 { await Task.yield() }

        XCTAssertEqual(Self.pullCount, 1,
                       "a refresh arriving mid-pull must join it, not issue a second request")
        XCTAssertEqual(settled, 0, "neither caller is settled while that pull is still running")

        // Twice, so a regression that did issue a second request fails the
        // assertion above rather than deadlocking here.
        held.signal()
        held.signal()
        await spin(until: { settled == 2 })
        XCTAssertEqual(settled, 2, "the one fetch releases both callers")
        service.stop()
    }

    private static var pullCount: Int { StubURLProtocol.seenPaths.filter { $0 == "/v1/sync" }.count }

    private func spin(until condition: () -> Bool, timeout: TimeInterval = 10) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
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

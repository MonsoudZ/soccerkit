import XCTest
@testable import SoccerCoachKit

/// The bug these cover: `performPush` built its request with
/// `upserts.compactMap { try? SyncWireCodec.dto(from: $0) }` and then returned
/// `true`. A record that failed wire encoding was therefore dropped from the
/// request *and* reported as landed, so `AppStore` advanced `lastSyncedRecords`
/// past it and it never appeared in another diff — silently unsynced for good,
/// with nothing shown to the coach.
///
/// A batch is acknowledged only when every record in it was.
@MainActor
final class SyncPushIntegrityTests: XCTestCase {
    /// Every service a test started. They own detached `Task`s, so a service left
    /// running outlives its test and its next request lands on the *shared* static
    /// `StubURLProtocol.responder` — failing whichever test is running by then.
    private var startedServices: [APISyncService] = []

    private func makeService() -> APISyncService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let tokens = TokenStore(storage: InMemoryTokenStorage())
        tokens.token = "access"
        let client = APIClient(baseURL: URL(string: "http://backend.test")!,
                               session: session, tokenProvider: { tokens.token })
        let service = APISyncService(client: client, namespace: "test",
                                     defaults: UserDefaults(suiteName: "push-integrity-\(UUID().uuidString)")!,
                                     tokenStore: tokens)
        startedServices.append(service)
        return service
    }

    /// A record whose payload isn't the JSON it claims to be, so
    /// `SyncWireCodec.dto(from:)` throws on it.
    private func unencodableRecord() -> SyncRecord {
        SyncRecord(type: .player, id: UUID().uuidString, payload: Data("not json".utf8))
    }

    private func goodRecord() -> SyncRecord {
        SyncRecords.records(from: TestData.snapshot(playerCount: 1)).first { $0.type == .player }!
    }

    /// Brings the service up (it refuses to push while stopped) and returns the
    /// upserts of each POST /v1/sync it makes.
    private func start(_ service: APISyncService, capturing onPush: @escaping ([SyncRecordDTO]) -> Void) {
        StubURLProtocol.responder = { req in
            switch (req.httpMethod ?? "", req.url?.path ?? "") {
            case ("GET", "/v1/sync"):
                return (200, Data(#"{"records":[],"deletes":[],"cursor":"1"}"#.utf8))
            case ("POST", "/v1/sync"):
                let request = try? JSONDecoder().decode(SyncPushRequest.self,
                                                        from: StubURLProtocol.body(of: req))
                onPush(request?.upserts ?? [])
                return (200, Data(#"{"conflicts":[],"cursor":"2"}"#.utf8))
            default:
                return (500, Data())
            }
        }
        let pulled = expectation(description: "service is running")
        service.onStatusChange = { if case .synced = $0 { pulled.fulfill() } }
        service.start()
        wait(for: [pulled], timeout: 20)
        service.onStatusChange = nil
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        startedServices = []
    }

    override func tearDown() {
        startedServices.forEach { $0.stop() }
        startedServices = []
        StubURLProtocol.reset()
        super.tearDown()
    }

    /// The fix: a batch that lost a record is not acknowledged, so `AppStore`
    /// holds its baseline and the record comes back in the next diff.
    func testBatchWithAnUnencodableRecordIsNotAcknowledged() {
        let service = makeService()
        start(service) { _ in }

        let landed = expectation(description: "push completes")
        var result: Bool?
        service.push(upserts: [goodRecord(), unencodableRecord()], deletes: []) {
            result = $0
            landed.fulfill()
        }
        wait(for: [landed], timeout: 20)

        XCTAssertEqual(result, false, "a batch that dropped a record must not report as landed")
    }

    /// The records that *did* encode still go up — one bad record must not
    /// withhold the rest of the coach's data.
    func testTheEncodableRecordsAreStillPushed() {
        let service = makeService()
        start(service) { _ in }

        let good = goodRecord()
        var pushed: [SyncRecordDTO] = []
        let landed = expectation(description: "push completes")
        StubURLProtocol.responder = { req in
            guard req.httpMethod == "POST" else { return (500, Data()) }
            let request = try? JSONDecoder().decode(SyncPushRequest.self,
                                                    from: StubURLProtocol.body(of: req))
            pushed = request?.upserts ?? []
            return (200, Data(#"{"conflicts":[],"cursor":"2"}"#.utf8))
        }
        service.push(upserts: [good, unencodableRecord()], deletes: []) { _ in landed.fulfill() }
        wait(for: [landed], timeout: 20)

        XCTAssertEqual(pushed.map(\.id), [good.id], "the encodable record must still reach the server")
    }

    /// The loss used to be silent. A dropped record now surfaces on the sync
    /// status line rather than passing as a clean sync.
    func testADroppedRecordSurfacesAsAFailure() {
        let service = makeService()
        start(service) { _ in }

        let reported = expectation(description: "a failure is surfaced")
        service.onStatusChange = { status in
            if case .failed = status { reported.fulfill() }
            if case .synced = status { XCTFail("an incomplete batch must not report as synced") }
        }
        service.push(upserts: [unencodableRecord()], deletes: []) { _ in }
        wait(for: [reported], timeout: 20)
    }

    /// The healthy path is unchanged: a fully-encodable batch is acknowledged.
    func testAFullyEncodableBatchIsAcknowledged() {
        let service = makeService()
        start(service) { _ in }

        let landed = expectation(description: "push completes")
        var result: Bool?
        service.push(upserts: [goodRecord()], deletes: []) {
            result = $0
            landed.fulfill()
        }
        wait(for: [landed], timeout: 20)

        XCTAssertEqual(result, true)
    }
}

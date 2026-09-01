import XCTest
@testable import SoccerCoachKit

/// The bug these cover: `AppStore` pushes only
/// `SyncRecords.diff(from: lastSyncedRecords, to: current)`, and it seeds that
/// baseline from the *local* snapshot in `init` — so the very first diff is
/// empty by construction. Without a bootstrap push, a coach's existing season
/// was never uploaded: sync carried only the edits made after it started, and
/// toggling it off and on again couldn't force a re-upload either.
///
/// The bootstrap lives in the sync services (behind `snapshotProvider`, which
/// the protocol already documented for exactly this) rather than in the store,
/// so both transports get it and the store's diff logic is untouched.
@MainActor
final class SyncBootstrapTests: XCTestCase {

    private func makeService(defaults: UserDefaults) -> (APISyncService, TokenStore) {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let tokens = TokenStore(storage: InMemoryTokenStorage())
        tokens.token = "access"
        let client = APIClient(baseURL: URL(string: "http://backend.test")!,
                               session: session, tokenProvider: { tokens.token })
        let service = APISyncService(client: client, namespace: "test",
                                     defaults: defaults, tokenStore: tokens)
        service.snapshotProvider = { TestData.snapshot(playerCount: 3) }
        return (service, tokens)
    }

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "bootstrap-tests-\(UUID().uuidString)")!
    }

    /// Records the upserts of every POST /v1/sync the service makes.
    private func capturePushes(_ onPush: @escaping ([SyncRecordDTO]) -> Void) {
        StubURLProtocol.responder = { req in
            switch (req.httpMethod ?? "", req.url?.path ?? "") {
            case ("GET", "/v1/sync"):
                return (200, Data(#"{"records":[],"deletes":[],"cursor":"1"}"#.utf8))
            case ("POST", "/v1/sync"):
                let body = req.httpBody ?? req.httpBodyStream.map { stream -> Data in
                    stream.open()
                    defer { stream.close() }
                    var data = Data()
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let read = stream.read(&buffer, maxLength: buffer.count)
                        if read <= 0 { break }
                        data.append(buffer, count: read)
                    }
                    return data
                } ?? Data()
                let request = try? JSONDecoder().decode(SyncPushRequest.self, from: body)
                onPush(request?.upserts ?? [])
                return (200, Data(#"{"conflicts":[],"cursor":"2"}"#.utf8))
            default:
                return (500, Data())
            }
        }
    }

    override func setUp() { super.setUp(); StubURLProtocol.reset() }
    override func tearDown() { StubURLProtocol.reset(); super.tearDown() }

    /// The fix: starting sync for the first time uploads what's already on the
    /// device, not nothing.
    func testFirstStartUploadsExistingData() {
        let defaults = freshDefaults()
        let (service, _) = makeService(defaults: defaults)
        let expected = SyncRecords.records(from: TestData.snapshot(playerCount: 3)).count
        XCTAssertGreaterThan(expected, 0, "the fixture must have something to upload")

        let pushed = expectation(description: "existing data is pushed")
        capturePushes { upserts in
            if upserts.count == expected { pushed.fulfill() }
        }
        service.start()
        wait(for: [pushed], timeout: 5)
    }

    /// And it happens once: a second launch against the same namespace must not
    /// re-upload the whole season.
    func testBootstrapDoesNotRepeatOnALaterStart() {
        let defaults = freshDefaults()
        let first = expectation(description: "first start bootstraps")
        capturePushes { _ in first.fulfill() }
        let (service, _) = makeService(defaults: defaults)
        service.start()
        wait(for: [first], timeout: 5)

        // A fresh service over the same namespace/defaults — i.e. the next launch.
        var pushCount = 0
        capturePushes { _ in pushCount += 1 }
        let (relaunched, _) = makeService(defaults: defaults)
        let pulled = expectation(description: "second start completes its pull")
        relaunched.onStatusChange = { if case .synced = $0 { pulled.fulfill() } }
        relaunched.start()
        wait(for: [pulled], timeout: 5)

        XCTAssertEqual(pushCount, 0, "an already-bootstrapped namespace must not re-upload everything")
    }

    /// A bootstrap the server never acknowledged must be retried, not marked done
    /// — otherwise one offline launch loses the upload permanently.
    func testFailedBootstrapIsRetriedOnTheNextStart() {
        let defaults = freshDefaults()
        let failed = expectation(description: "first bootstrap attempt fails")
        StubURLProtocol.responder = { req in
            switch (req.httpMethod ?? "", req.url?.path ?? "") {
            case ("GET", "/v1/sync"):
                return (200, Data(#"{"records":[],"deletes":[],"cursor":"1"}"#.utf8))
            case ("POST", "/v1/sync"):
                failed.fulfill()
                return (500, Data())
            default:
                return (500, Data())
            }
        }
        let (service, _) = makeService(defaults: defaults)
        service.start()
        wait(for: [failed], timeout: 5)

        let retried = expectation(description: "the next start retries the bootstrap")
        capturePushes { _ in retried.fulfill() }
        let (relaunched, _) = makeService(defaults: defaults)
        relaunched.start()
        wait(for: [retried], timeout: 5)
    }

    /// Purging the account drops the bootstrap flag: the server's copy is gone,
    /// so a later sync has to upload from scratch rather than trust it.
    func testPurgeClearsTheBootstrapFlag() {
        let defaults = freshDefaults()
        let bootstrapped = expectation(description: "bootstrap lands")
        capturePushes { _ in bootstrapped.fulfill() }
        let (service, _) = makeService(defaults: defaults)
        service.start()
        wait(for: [bootstrapped], timeout: 5)

        StubURLProtocol.responder = { req in
            (req.httpMethod == "DELETE" && req.url?.path == "/v1/me") ? (204, Data()) : (500, Data())
        }
        let purged = expectation(description: "purge completes")
        service.purge { XCTAssertTrue($0); purged.fulfill() }
        wait(for: [purged], timeout: 5)

        let reUploaded = expectation(description: "a later start uploads again")
        capturePushes { _ in reUploaded.fulfill() }
        let (relaunched, _) = makeService(defaults: defaults)
        relaunched.start()
        wait(for: [reUploaded], timeout: 5)
    }
}

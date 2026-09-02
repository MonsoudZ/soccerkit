import XCTest
@testable import SoccerCoachKit

/// Thread-safe record of what the stub saw pushed. The responder runs on a
/// URLSession thread, not the test's, so the counters it keeps can't be plain
/// vars on the test case.
final class PushRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var batches: [[SyncRecordDTO]] = []

    func record(_ upserts: [SyncRecordDTO]) {
        lock.lock(); defer { lock.unlock() }
        batches.append(upserts)
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return batches.count }
    var last: [SyncRecordDTO]? { lock.lock(); defer { lock.unlock() }; return batches.last }
    func reset() { lock.lock(); defer { lock.unlock() }; batches.removeAll() }
}

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
///
/// # On the flakiness this suite used to have
///
/// It broke `main` three times, and the diagnosis in `05cc09b` — that a loaded
/// runner was outrunning a 5s wait — was wrong. The waits were returning too
/// *early*, not too late.
///
/// Every test fulfilled its expectation from inside the stub's response
/// handler, which runs when the request is *seen*. `wait` therefore returned
/// while the push was still in flight, before `bootstrapIfNeeded` had recorded
/// its result. The next phase then started a service against a namespace whose
/// flag hadn't been written yet, so it bootstrapped a second time — that is the
/// "already-bootstrapped namespace must not re-upload" failure. Worse, that
/// stray push landed on the *next test's* responder, which is a shared static,
/// and fulfilled an expectation that was already fulfilled. Over-fulfilling
/// raises an XCTest API violation from a URLSession thread, where nothing
/// catches it, so the test host aborted and the whole suite restarted.
///
/// Two changes make it deterministic. Tests now wait on the durable outcome —
/// the bootstrap flag, or a status the service actually reported — rather than
/// on a request being seen. And each test answers only on its own host, so a
/// service an earlier test left in flight gets a 500 instead of driving a live
/// test's expectations.
@MainActor
final class SyncBootstrapTests: XCTestCase {
    /// Every service a test started, stopped in `tearDown` so a service left
    /// running doesn't outlive its test.
    private var startedServices: [APISyncService] = []
    /// Unique per test, so an earlier test's stray traffic is identifiable and
    /// can be refused rather than answered.
    private var host = ""
    private var defaults: UserDefaults!

    /// The namespace every service here syncs under, and the durable flag that
    /// records whether its bootstrap has landed.
    private let namespace = "test"
    private var bootstrapKey: String { "apiSyncBootstrapped.\(namespace)" }

    /// Waits are on stubbed responses, so a healthy run returns in
    /// milliseconds; the ceiling only has to outlast a loaded CI runner.
    private let timeout: TimeInterval = 20

    override func setUp() {
        super.setUp()
        StubURLProtocol.reset()
        startedServices = []
        host = "backend-\(UUID().uuidString).test"
        defaults = UserDefaults(suiteName: "bootstrap-tests-\(UUID().uuidString)")!
    }

    override func tearDown() {
        startedServices.forEach { $0.stop() }
        startedServices = []
        StubURLProtocol.reset()
        super.tearDown()
    }

    private func makeService() -> APISyncService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        let tokens = TokenStore(storage: InMemoryTokenStorage())
        tokens.token = "access"
        let client = APIClient(baseURL: URL(string: "http://\(host)")!,
                               session: session, tokenProvider: { tokens.token })
        let service = APISyncService(client: client, namespace: namespace,
                                     defaults: defaults, tokenStore: tokens)
        service.snapshotProvider = { TestData.snapshot(playerCount: 3) }
        startedServices.append(service)
        return service
    }

    // MARK: - Stubbing

    /// Installs a responder that answers only this test's host. A service an
    /// earlier test left in flight keeps its own host, so its late requests fall
    /// through to a 500 instead of reaching this test's expectations.
    private func respond(_ handler: @escaping (URLRequest) -> (Int, Data)?) {
        let host = self.host
        StubURLProtocol.responder = { request in
            guard request.url?.host == host else { return (500, Data()) }
            return handler(request) ?? (500, Data())
        }
    }

    private static let emptyPull = Data(#"{"records":[],"deletes":[],"cursor":"1"}"#.utf8)
    private static let acceptedPush = Data(#"{"conflicts":[],"cursor":"2"}"#.utf8)

    /// Pulls return nothing; pushes are recorded and accepted.
    private func acceptPushes(recordingInto pushes: PushRecorder) {
        respond { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/v1/sync"):
                return (200, Self.emptyPull)
            case ("POST", "/v1/sync"):
                let body = StubURLProtocol.body(of: request)
                let decoded = try? JSONDecoder().decode(SyncPushRequest.self, from: body)
                pushes.record(decoded?.upserts ?? [])
                return (200, Self.acceptedPush)
            default:
                return nil
            }
        }
    }

    // MARK: - Waiting on outcomes

    /// Waits for the durable flag rather than for a request to be seen — the
    /// bootstrap is only done once the server's answer has come back and been
    /// recorded, which is exactly what the next phase depends on.
    private func waitForBootstrapFlag(_ expected: Bool,
                                      file: StaticString = #filePath, line: UInt = #line) {
        let defaults = self.defaults!
        let key = bootstrapKey
        let reached = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in defaults.bool(forKey: key) == expected },
            object: nil
        )
        wait(for: [reached], timeout: timeout)
        XCTAssertEqual(defaults.bool(forKey: key), expected, file: file, line: line)
    }

    /// A status the service itself reported, which is emitted after the response
    /// has been handled. Over-fulfilment is allowed: a service reports several
    /// statuses in a run, and an over-fulfilled expectation aborts the host.
    private func expectStatus(_ service: APISyncService, _ description: String,
                              matching: @escaping (SyncStatus) -> Bool) -> XCTestExpectation {
        let reported = expectation(description: description)
        reported.assertForOverFulfill = false
        service.onStatusChange = { if matching($0) { reported.fulfill() } }
        return reported
    }

    /// Gives a service's `start` task room to finish, so an assertion that it
    /// did *not* push has given it the chance to. `bootstrapIfNeeded` is awaited
    /// after the pull, so the pull completing isn't the end of the sequence.
    private func settle() {
        let settled = expectation(description: "the start task finishes")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { settled.fulfill() }
        wait(for: [settled], timeout: timeout)
    }

    // MARK: - Tests

    /// The fix: starting sync for the first time uploads what's already on the
    /// device, not nothing.
    func testFirstStartUploadsExistingData() {
        let expected = SyncRecords.records(from: TestData.snapshot(playerCount: 3)).count
        XCTAssertGreaterThan(expected, 0, "the fixture must have something to upload")

        let pushes = PushRecorder()
        acceptPushes(recordingInto: pushes)
        makeService().start()

        waitForBootstrapFlag(true)
        XCTAssertEqual(pushes.last?.count, expected,
                       "the whole snapshot goes up, not a diff against itself")
    }

    /// And it happens once: a second launch against the same namespace must not
    /// re-upload the whole season.
    func testBootstrapDoesNotRepeatOnALaterStart() {
        let pushes = PushRecorder()
        acceptPushes(recordingInto: pushes)
        let service = makeService()
        service.start()
        waitForBootstrapFlag(true)
        service.stop() // so only the relaunched service below can push

        // A fresh service over the same namespace/defaults — i.e. the next launch.
        pushes.reset()
        let relaunched = makeService()
        let pulled = expectStatus(relaunched, "the second start completes its pull") {
            if case .synced = $0 { return true } else { return false }
        }
        relaunched.start()
        wait(for: [pulled], timeout: timeout)
        settle()

        XCTAssertEqual(pushes.count, 0,
                       "an already-bootstrapped namespace must not re-upload everything")
    }

    /// A bootstrap the server never acknowledged must be retried, not marked done
    /// — otherwise one offline launch loses the upload permanently.
    func testFailedBootstrapIsRetriedOnTheNextStart() {
        let pushes = PushRecorder()
        respond { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/v1/sync"):
                return (200, Self.emptyPull)
            case ("POST", "/v1/sync"):
                pushes.record([])
                return (500, Data())
            default:
                return nil
            }
        }
        let service = makeService()
        let rejected = expectStatus(service, "the bootstrap push is rejected") {
            if case .failed = $0 { return true } else { return false }
        }
        service.start()
        wait(for: [rejected], timeout: timeout)
        XCTAssertGreaterThan(pushes.count, 0, "it did try")
        XCTAssertFalse(defaults.bool(forKey: bootstrapKey),
                       "a bootstrap the server rejected is not recorded as done")
        service.stop() // only the relaunched service may drive phase two

        pushes.reset()
        acceptPushes(recordingInto: pushes)
        makeService().start()

        waitForBootstrapFlag(true)
        XCTAssertGreaterThan(pushes.count, 0, "the next start retries the upload")
    }

    /// Purging the account drops the bootstrap flag: the server's copy is gone,
    /// so a later sync has to upload from scratch rather than trust it.
    func testPurgeClearsTheBootstrapFlag() {
        let pushes = PushRecorder()
        acceptPushes(recordingInto: pushes)
        let service = makeService()
        service.start()
        waitForBootstrapFlag(true)
        service.stop()

        respond { request in
            (request.httpMethod == "DELETE" && request.url?.path == "/v1/me") ? (204, Data()) : nil
        }
        let purged = expectation(description: "purge completes")
        service.purge { XCTAssertTrue($0); purged.fulfill() }
        wait(for: [purged], timeout: timeout)
        XCTAssertFalse(defaults.bool(forKey: bootstrapKey), "purge drops the flag")

        pushes.reset()
        acceptPushes(recordingInto: pushes)
        makeService().start()

        waitForBootstrapFlag(true)
        XCTAssertGreaterThan(pushes.count, 0, "a later start uploads again")
    }
}

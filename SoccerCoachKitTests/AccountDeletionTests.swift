import XCTest
@testable import SoccerCoachKit

@MainActor
final class AccountDeletionTests: XCTestCase {
    private func isEmpty(_ result: PersistenceLoadResult) -> Bool {
        if case .empty = result { return true }
        return false
    }

    func testDeleteAccountPurgesRemoteThenLocalOnSuccess() async {
        let mock = MockRemoteSync()
        mock.purgeResult = true
        let persistence = InMemoryPersistence()
        let store = AppStore(snapshot: TestData.snapshot(), persistence: persistence, remoteSync: mock)
        store.addTeam(name: "Keep", ageGroup: .u10, season: "2026") // force a persist
        XCTAssertFalse(isEmpty(persistence.load()), "precondition: data is stored")

        let ok = await store.deleteAccount()

        XCTAssertTrue(ok)
        XCTAssertTrue(mock.purgeCalled, "remote data must be purged")
        XCTAssertTrue(isEmpty(persistence.load()), "the local partition must be wiped")
    }

    /// If the remote deletion fails, nothing local is wiped — the app must never
    /// report success while server data survives.
    func testDeleteAccountAbortsWhenRemotePurgeFails() async {
        let mock = MockRemoteSync()
        mock.purgeResult = false
        let persistence = InMemoryPersistence()
        let store = AppStore(snapshot: TestData.snapshot(), persistence: persistence, remoteSync: mock)
        store.addTeam(name: "Keep", ageGroup: .u10, season: "2026")

        let ok = await store.deleteAccount()

        XCTAssertFalse(ok)
        XCTAssertTrue(mock.purgeCalled)
        XCTAssertFalse(isEmpty(persistence.load()), "local data must survive a failed remote deletion")
    }

    func testPersistencePurgeRemovesSnapshotAndCorruptBackup() {
        let defaults = UserDefaults(suiteName: "purge-tests-\(UUID().uuidString)")!
        let persistence = UserDefaultsPersistenceService(defaults: defaults, namespace: "coach-1")
        persistence.save(TestData.snapshot())
        persistence.flushPendingSync()
        persistence.backupCorruptData(Data("unreadable".utf8))
        XCTAssertFalse(isEmpty(persistence.load()))
        XCTAssertNotNil(persistence.corruptBackup())

        persistence.purge()

        XCTAssertTrue(isEmpty(persistence.load()), "snapshot removed")
        XCTAssertNil(persistence.corruptBackup(), "corrupt backup removed")
    }
}

final class DeleteAccountClientTests: XCTestCase {
    func testDeleteAccountCallsDeleteMe() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        StubURLProtocol.reset()
        StubURLProtocol.responder = { req in
            (req.httpMethod == "DELETE" && req.url?.path == "/v1/me") ? (204, Data()) : (500, Data())
        }
        defer { StubURLProtocol.reset() }

        let client = APIClient(baseURL: URL(string: "http://backend.test")!,
                               session: session, tokenProvider: { "tok" })
        try await client.deleteAccount() // must not throw on 204
        XCTAssertTrue(StubURLProtocol.seenPaths.contains("/v1/me"))
    }

    func testDeleteAccountThrowsOnServerError() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: config)
        StubURLProtocol.reset()
        StubURLProtocol.responder = { _ in (500, Data()) }
        defer { StubURLProtocol.reset() }

        let client = APIClient(baseURL: URL(string: "http://backend.test")!,
                               session: session, tokenProvider: { "tok" })
        do {
            try await client.deleteAccount()
            XCTFail("a 500 must throw")
        } catch {
            // expected
        }
    }
}

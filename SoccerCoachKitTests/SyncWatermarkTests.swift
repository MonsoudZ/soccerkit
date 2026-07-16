import XCTest
@testable import SoccerCoachKit

/// A `RemoteSyncService` that records every pushed batch and lets the test decide
/// whether the push "landed". Used to prove `AppStore` advances its sync baseline
/// only on a successful push — so a failed push isn't erased from the next diff.
@MainActor
final class MockRemoteSync: RemoteSyncService {
    var snapshotProvider: (() -> AppSnapshot)?
    var applyRemoteChanges: ((_ upserts: [SyncRecord], _ deletes: [SyncRecordKey]) -> Void)?
    var onStatusChange: ((SyncStatus) -> Void)?

    /// The upserts of every push, in order.
    var pushedUpserts: [[SyncRecord]] = []
    /// What each push's completion reports. `true` = the batch landed.
    var result = true

    func start() {}
    func stop() {}
    func setNamespace(_ namespace: String?) {}
    func push(upserts: [SyncRecord], deletes: [SyncRecordKey], completion: @escaping (Bool) -> Void) {
        pushedUpserts.append(upserts)
        completion(result)
    }
}

@MainActor
final class SyncWatermarkTests: XCTestCase {
    private func makeStore(_ mock: MockRemoteSync) -> AppStore {
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 1),
                             persistence: InMemoryPersistence(), remoteSync: mock)
        store.cloudSyncEnabled = true
        mock.pushedUpserts.removeAll() // ignore any bootstrap push from enabling sync
        return store
    }

    private func ids(_ batch: [SyncRecord]?) -> Set<String> { Set((batch ?? []).map(\.id)) }

    /// The bug: the baseline advanced in a `defer`, before the fire-and-forget push
    /// had even started, so a failed push was dropped from the next diff forever.
    /// A failed push must instead keep its records for the next diff.
    func testFailedPushKeepsItsRecordsInTheNextDiff() {
        let mock = MockRemoteSync()
        mock.result = false // every push fails
        let store = makeStore(mock)
        let teamID = store.teams[0].id

        let p1 = TestData.player(teamID: teamID, number: 10)
        store.addPlayer(p1, toTeam: teamID)
        XCTAssertTrue(ids(mock.pushedUpserts.last).contains(p1.id.uuidString),
                      "the first push should carry p1")

        let p2 = TestData.player(teamID: teamID, number: 11)
        store.addPlayer(p2, toTeam: teamID)
        let latest = ids(mock.pushedUpserts.last)
        XCTAssertTrue(latest.contains(p1.id.uuidString),
                      "p1's failed push must still be in the next diff, not lost")
        XCTAssertTrue(latest.contains(p2.id.uuidString))
    }

    /// The other half: a push that lands advances the baseline, so an acked record
    /// is not re-pushed on the next edit.
    func testSuccessfulPushAdvancesTheBaseline() {
        let mock = MockRemoteSync()
        mock.result = true
        let store = makeStore(mock)
        let teamID = store.teams[0].id

        let p1 = TestData.player(teamID: teamID, number: 10)
        store.addPlayer(p1, toTeam: teamID)

        let p2 = TestData.player(teamID: teamID, number: 11)
        store.addPlayer(p2, toTeam: teamID)
        let latest = ids(mock.pushedUpserts.last)
        XCTAssertFalse(latest.contains(p1.id.uuidString),
                       "p1 was acknowledged; it must not be re-pushed")
        XCTAssertTrue(latest.contains(p2.id.uuidString))
    }
}

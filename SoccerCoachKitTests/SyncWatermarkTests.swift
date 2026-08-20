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
    /// The deletes of every push, in order.
    var pushedDeletes: [[SyncRecordKey]] = []
    /// What each push's completion reports. `true` = the batch landed.
    var result = true

    /// What `purge` reports, and whether it was called.
    var purgeResult = true
    private(set) var purgeCalled = false

    func start() {}
    func stop() {}
    func setNamespace(_ namespace: String?) {}
    func push(upserts: [SyncRecord], deletes: [SyncRecordKey], completion: @escaping (Bool) -> Void) {
        pushedUpserts.append(upserts)
        pushedDeletes.append(deletes)
        completion(result)
    }
    func purge(completion: @escaping (Bool) -> Void) {
        purgeCalled = true
        completion(purgeResult)
    }
}

@MainActor
final class SyncWatermarkTests: XCTestCase {
    private func makeStore(_ mock: MockRemoteSync) -> AppStore {
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 1),
                             persistence: InMemoryPersistence(), remoteSync: mock)
        store.cloudSyncEnabled = true
        store.flushPendingRemoteSync()
        mock.pushedUpserts.removeAll() // ignore any bootstrap push from enabling sync
        return store
    }

    /// The diff runs off the main actor, so a test has to flush it to observe the
    /// push at the point it asserts rather than whenever the background task lands.
    private func addPlayer(_ player: Player, to teamID: UUID, in store: AppStore) {
        store.addPlayer(player, toTeam: teamID)
        store.flushPendingRemoteSync()
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
        addPlayer(p1, to: teamID, in: store)
        XCTAssertTrue(ids(mock.pushedUpserts.last).contains(p1.id.uuidString),
                      "the first push should carry p1")

        let p2 = TestData.player(teamID: teamID, number: 11)
        addPlayer(p2, to: teamID, in: store)
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
        addPlayer(p1, to: teamID, in: store)

        let p2 = TestData.player(teamID: teamID, number: 11)
        addPlayer(p2, to: teamID, in: store)
        let latest = ids(mock.pushedUpserts.last)
        XCTAssertFalse(latest.contains(p1.id.uuidString),
                       "p1 was acknowledged; it must not be re-pushed")
        XCTAssertTrue(latest.contains(p2.id.uuidString))
    }

    /// The point of deferring the diff: a burst of edits costs one encode of the
    /// season rather than one each. The pass can only complete back on the main
    /// actor, which a synchronous test body never yields to, so the burst is
    /// guaranteed to still be pending when the flush picks it up.
    func testABurstOfEditsCoalescesIntoASinglePush() {
        let mock = MockRemoteSync()
        let store = makeStore(mock)
        let teamID = store.teams[0].id

        let added = (10...12).map { TestData.player(teamID: teamID, number: $0) }
        for player in added { store.addPlayer(player, toTeam: teamID) }
        XCTAssertTrue(mock.pushedUpserts.isEmpty, "The diff is deferred, not run per edit")

        store.flushPendingRemoteSync()

        XCTAssertEqual(mock.pushedUpserts.count, 1, "One push carries the whole burst")
        let pushed = ids(mock.pushedUpserts.last)
        for player in added {
            XCTAssertTrue(pushed.contains(player.id.uuidString), "\(player.name) is in it")
        }
    }

    /// Adopting a remote change as the baseline has to stay synchronous. It is
    /// guarded by a flag that is only set for the duration of the restore, so a
    /// deferred pass would run after it cleared and push the server's own change
    /// straight back at it.
    func testAChangeAppliedFromTheRemoteIsNotEchoedBack() {
        let mock = MockRemoteSync()
        let store = makeStore(mock)

        let team = TestData.team()
        let remote = AppSnapshot(teams: [team], players: [], drills: [], sessions: [],
                                 diagrams: [], games: [], events: [], selectedTeamID: team.id)
        mock.applyRemoteChanges?(SyncRecords.records(from: remote), [])
        store.flushPendingRemoteSync()

        XCTAssertTrue(store.teams.contains { $0.id == team.id }, "The remote change was applied")
        XCTAssertTrue(mock.pushedUpserts.isEmpty,
                      "A change that came from the server is not pushed back at it")
    }
}

import XCTest
@testable import SoccerCoachKit

/// The bug these cover: `AppStore` held its sync baseline only in memory and
/// rebuilt it from the local snapshot in `init` — which amounts to declaring
/// "the remote already has everything I have" before talking to the remote at
/// all. `36074ba` made a *failed* push hold the baseline so the records retry,
/// but a relaunch erased that: the held-back edit was folded into the new
/// baseline and never appeared in another diff.
///
/// So an edit made offline, followed by the app being killed, was unsynced for
/// good — unless that record happened to be touched again later.
@MainActor
final class SyncWatermarkDurabilityTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "watermark-\(UUID().uuidString)")!
    }

    private func makeStore(_ mock: MockRemoteSync, namespace: String?) -> AppStore {
        UserDefaults.standard.set(true, forKey: "iCloudSyncEnabled")
        return AppStore(snapshot: TestData.snapshot(playerCount: 2),
                        persistence: InMemoryPersistence(), remoteSync: mock,
                        namespace: namespace)
    }

    private func ids(_ batches: [[SyncRecord]]) -> Set<String> {
        Set(batches.flatMap { $0 }.map(\.id))
    }

    /// The same data coming back on the next launch. Round-tripped through the
    /// store's own export rather than reaching into its private snapshot.
    private func relaunchSnapshot(of store: AppStore) throws -> AppSnapshot {
        let data = try XCTUnwrap(store.exportData())
        return try JSONDecoder().decode(AppSnapshot.self, from: data)
    }

    // MARK: - The digest layer

    /// The fingerprint has to be stable across launches. Swift seeds `hashValue`
    /// per process, so a watermark built from it would mark everything changed
    /// every launch — SHA-256 is used precisely to avoid that.
    func testDigestIsStableForIdenticalPayloads() {
        let payload = Data("the same bytes".utf8)
        XCTAssertEqual(SyncRecords.digest(payload), SyncRecords.digest(Data("the same bytes".utf8)))
        XCTAssertNotEqual(SyncRecords.digest(payload), SyncRecords.digest(Data("other bytes".utf8)))
    }

    func testDiffFromDigestsMatchesDiffFromRecords() {
        let base = SyncRecords.records(from: TestData.snapshot(playerCount: 2))
        var changed = TestData.snapshot(playerCount: 2)
        changed.teams[0].name = "Renamed"
        let new = SyncRecords.records(from: changed)

        let viaRecords = SyncRecords.diff(from: base, to: new)
        let viaDigests = SyncRecords.diff(fromDigests: SyncRecords.digests(from: base), to: new)

        XCTAssertEqual(Set(viaRecords.upserts.map(\.id)), Set(viaDigests.upserts.map(\.id)))
        XCTAssertEqual(Set(viaRecords.deletes.map(\.id)), Set(viaDigests.deletes.map(\.id)))
    }

    // MARK: - The store

    /// The headline fix: an edit whose push failed is still pending after a
    /// relaunch, instead of being absorbed into a fresh baseline.
    func testAnUnsyncedEditSurvivesARelaunch() throws {
        let namespace = "coach-\(UUID().uuidString)"
        let offline = MockRemoteSync()
        offline.result = false // the remote is unreachable

        let store = makeStore(offline, namespace: namespace)
        offline.pushedUpserts.removeAll()
        let teamID = store.teams[0].id
        let player = TestData.player(teamID: teamID, number: 21)
        store.addPlayer(player, toTeam: teamID)
        XCTAssertTrue(ids(offline.pushedUpserts).contains(player.id.uuidString),
                      "the offline push should have been attempted")

        // The app suspends (which is what writes the baseline), then relaunches
        // with the same data and a remote that now works.
        store.flushPendingWrites()
        let online = MockRemoteSync()
        let relaunched = AppStore(snapshot: try relaunchSnapshot(of: store),
                                  persistence: InMemoryPersistence(), remoteSync: online,
                                  namespace: namespace)
        relaunched.teams[0].name = "Touched" // any edit triggers the next diff

        XCTAssertTrue(ids(online.pushedUpserts).contains(player.id.uuidString),
                      "the player whose push never landed must still be pending after relaunch")
    }

    /// The complement: a record the remote acknowledged is not re-pushed after a
    /// relaunch, or every launch would re-upload the whole season.
    func testAnAcknowledgedRecordIsNotRePushedAfterARelaunch() throws {
        let namespace = "coach-\(UUID().uuidString)"
        let online = MockRemoteSync()
        let store = makeStore(online, namespace: namespace)
        let teamID = store.teams[0].id
        let player = TestData.player(teamID: teamID, number: 22)
        store.addPlayer(player, toTeam: teamID)
        store.flushPendingWrites()

        let next = MockRemoteSync()
        let relaunched = AppStore(snapshot: try relaunchSnapshot(of: store),
                                  persistence: InMemoryPersistence(), remoteSync: next,
                                  namespace: namespace)
        relaunched.teams[0].name = "Touched"

        XCTAssertFalse(ids(next.pushedUpserts).contains(player.id.uuidString),
                       "an acknowledged record must not be re-pushed on every launch")
    }

    /// With no stored baseline — the first launch after this shipped — the store
    /// falls back to the local snapshot rather than re-pushing everything. The
    /// services' one-time bootstrap owns the initial full upload.
    func testAFreshNamespaceDoesNotRePushEverything() {
        let mock = MockRemoteSync()
        let store = makeStore(mock, namespace: "never-seen-\(UUID().uuidString)")
        mock.pushedUpserts.removeAll()

        store.teams[0].name = "Touched"

        let pushed = ids(mock.pushedUpserts)
        XCTAssertTrue(pushed.contains(store.teams[0].id.uuidString), "the edited record goes up")
        XCTAssertFalse(pushed.contains(store.players[0].id.uuidString),
                       "untouched records must not be swept into the first diff")
    }

    // MARK: - The store itself

    func testWatermarkRoundTripsThroughStorage() {
        let defaults = freshDefaults()
        let store = SyncWatermarkStore(namespace: "coach", defaults: defaults)
        XCTAssertNil(store.load(), "an unseen namespace has no baseline")

        let digests = SyncRecords.digests(from: SyncRecords.records(from: TestData.snapshot(playerCount: 2)))
        store.save(digests)

        XCTAssertEqual(SyncWatermarkStore(namespace: "coach", defaults: defaults).load(), digests)
    }

    /// Two coaches on one device sync against different remotes, so they must not
    /// share a baseline.
    func testNamespacesAreIsolated() {
        let defaults = freshDefaults()
        let digests = SyncRecords.digests(from: SyncRecords.records(from: TestData.snapshot(playerCount: 1)))
        SyncWatermarkStore(namespace: "coach-a", defaults: defaults).save(digests)

        XCTAssertNil(SyncWatermarkStore(namespace: "coach-b", defaults: defaults).load())
        XCTAssertNotNil(SyncWatermarkStore(namespace: "coach-a", defaults: defaults).load())
    }

    func testClearDropsTheBaseline() {
        let defaults = freshDefaults()
        let store = SyncWatermarkStore(namespace: "coach", defaults: defaults)
        store.save(SyncRecords.digests(from: SyncRecords.records(from: TestData.snapshot(playerCount: 1))))
        store.clear()
        XCTAssertNil(store.load())
    }
}

import XCTest
@testable import SoccerCoachKit

/// A remote sync can delete this device's last team when two devices hold
/// different team sets (this device has only X; another, which also has Y so its
/// delete is allowed, deletes X). The store must recover into a valid state
/// rather than leave `teams` empty and trap the next `selectedTeam` read.
@MainActor
final class RemoteTeamDeletionTests: XCTestCase {
    func testRemoteDeleteOfLastTeamRecoversInsteadOfEmptying() {
        let mock = MockRemoteSync()
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 1),
                             persistence: InMemoryPersistence(), remoteSync: mock)
        let teamID = store.teams[0].id
        XCTAssertEqual(store.teams.count, 1)

        // The server tombstones the only team the device has.
        mock.applyRemoteChanges?([], [SyncRecordKey(.team, teamID.uuidString)])

        // The invariant the whole UI depends on must still hold.
        XCTAssertFalse(store.teams.isEmpty,
                       "a remote delete of the last team must recover, not empty the store")
        XCTAssertTrue(store.teams.contains { $0.id == store.selectedTeamID },
                      "selectedTeamID must point at a team that exists")
        // Must not trap: this is the read that crashed before the fix.
        XCTAssertNotNil(store.selectedTeam)
        // The deleted team is gone; the recovery team took its place.
        XCTAssertFalse(store.teams.contains { $0.id == teamID })
    }

    /// Constructing the store from a snapshot that somehow has no teams (a
    /// corrupt or empty remote payload) must also land in a valid state.
    func testEmptySnapshotStillYieldsACurrentTeam() {
        let empty = AppSnapshot(teams: [], players: [], drills: [], sessions: [],
                                diagrams: [], games: [], events: [], selectedTeamID: UUID())
        let store = AppStore(snapshot: empty, persistence: InMemoryPersistence())
        XCTAssertFalse(store.teams.isEmpty)
        XCTAssertTrue(store.teams.contains { $0.id == store.selectedTeamID })
        XCTAssertNotNil(store.selectedTeam)
    }
}

/// Applying a remote change can make the store change something of its own:
/// `restore` invents a recovery team when a remote delete empties `teams`, and
/// re-points `selectedTeamID` when the stored one is gone. Those are local edits,
/// and the remote has never seen them — so the baseline must not mark them synced.
@MainActor
final class RemoteApplyBaselineTests: XCTestCase {
    private func makeStore(_ mock: MockRemoteSync) -> AppStore {
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 1),
                             persistence: InMemoryPersistence(), remoteSync: mock)
        store.cloudSyncEnabled = true
        mock.pushes.removeAll()
        return store
    }

    private func pushedTeamIDs(_ mock: MockRemoteSync) -> Set<String> {
        Set(mock.pushes.flatMap(\.upserts).filter { $0.type == .team }.map(\.id))
    }

    /// The bug: each device that lost its last team recovered into a private team
    /// of its own that was never uploaded, so they never converged.
    func testARecoveryTeamIsUploadedRatherThanBankedAsSynced() {
        let mock = MockRemoteSync()
        let store = makeStore(mock)
        let deleted = store.teams[0].id

        mock.applyRemoteChanges?([], [SyncRecordKey(.team, deleted.uuidString)])

        let recovered = store.teams[0].id
        XCTAssertNotEqual(recovered, deleted, "precondition: a new team was invented locally")
        XCTAssertTrue(pushedTeamIDs(mock).contains(recovered.uuidString),
                      "the invented team must reach the remote; pushed: \(pushedTeamIDs(mock))")
    }

    /// It must still hold back what the remote just sent, or every pull would
    /// bounce straight back as a push.
    func testRecordsTheRemoteSentAreNotEchoedBack() {
        let mock = MockRemoteSync()
        let store = makeStore(mock)

        var incoming = store.teams[0]
        incoming.name = "Renamed By Another Device"
        let payload = try! JSONEncoder().encode(incoming) // matches SyncRecords' encoder
        mock.applyRemoteChanges?([SyncRecord(type: .team, id: incoming.id.uuidString,
                                             payload: payload)], [])

        XCTAssertEqual(store.teams[0].name, "Renamed By Another Device", "the change was applied")
        XCTAssertFalse(pushedTeamIDs(mock).contains(incoming.id.uuidString),
                       "a record the remote sent must not be pushed back at it")
    }

    /// A tombstone the remote sent must not come back as a delete we push.
    func testADeleteTheRemoteSentIsNotEchoedBack() {
        let mock = MockRemoteSync()
        let store = makeStore(mock)
        // A second team, so deleting the first doesn't trigger the recovery path.
        store.addTeam(name: "Second", ageGroup: .u10, season: "2026")
        let doomed = store.teams[0].id
        mock.pushes.removeAll()

        mock.applyRemoteChanges?([], [SyncRecordKey(.team, doomed.uuidString)])

        XCTAssertFalse(store.teams.contains { $0.id == doomed }, "the delete was applied")
        let pushedDeletes = Set(mock.pushes.flatMap(\.deletes).map(\.id))
        XCTAssertFalse(pushedDeletes.contains(doomed.uuidString),
                       "a tombstone the remote sent must not be pushed back at it")
    }

    /// Local edits made before the pull are still owed to the remote afterwards —
    /// adopting only the applied keys must not quietly forgive the rest.
    func testAnUnsyncedLocalEditSurvivesAPull() {
        let mock = MockRemoteSync()
        mock.result = false // the remote is unreachable, so the edit is held back
        let store = makeStore(mock)
        store.addTeam(name: "Made While Offline", ageGroup: .u12, season: "2026")
        let offline = store.teams.first { $0.name == "Made While Offline" }!.id

        mock.result = true
        mock.pushes.removeAll()
        // An unrelated record arrives from the remote.
        var other = store.teams[0]
        other.name = "Touched Elsewhere"
        mock.applyRemoteChanges?([SyncRecord(type: .team, id: other.id.uuidString,
                                             payload: try! JSONEncoder().encode(other))], [])

        XCTAssertTrue(pushedTeamIDs(mock).contains(offline.uuidString),
                      "the offline edit is still owed to the remote after a pull")
    }
}

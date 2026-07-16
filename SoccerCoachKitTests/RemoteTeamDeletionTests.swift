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

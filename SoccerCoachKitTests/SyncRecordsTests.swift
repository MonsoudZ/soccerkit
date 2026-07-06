import XCTest
@testable import SoccerCoachKit

/// Tests the pure record-mapping/diff layer that drives CloudKit sync. (The
/// CKSyncEngine wiring itself needs on-device validation.)
final class SyncRecordsTests: XCTestCase {
    private func emptySnapshot(selectedTeamID: UUID) -> AppSnapshot {
        AppSnapshot(teams: [], players: [], drills: [], sessions: [],
                    diagrams: [], games: [], events: [], selectedTeamID: selectedTeamID)
    }

    func testRecordsRoundTripReconstructsTheSnapshot() {
        let snapshot = TestData.snapshot(playerCount: 3)
        let records = SyncRecords.records(from: snapshot)

        var rebuilt = emptySnapshot(selectedTeamID: UUID())
        for record in records { SyncRecords.apply(record, to: &rebuilt) }

        XCTAssertEqual(rebuilt.teams.map(\.id).sorted(), snapshot.teams.map(\.id).sorted())
        XCTAssertEqual(rebuilt.players.map(\.id).sorted(), snapshot.players.map(\.id).sorted())
        XCTAssertEqual(rebuilt.selectedTeamID, snapshot.selectedTeamID, "prefs record carries the selected team")
    }

    func testDiffDetectsAddsAndEdits() {
        let snapshot = TestData.snapshot(playerCount: 2)
        let base = SyncRecords.records(from: snapshot)

        var changed = snapshot
        changed.players[0].name = "Renamed Player"     // edit
        changed.teams.append(TestData.team())          // add

        let (upserts, deletes) = SyncRecords.diff(from: base, to: SyncRecords.records(from: changed))

        XCTAssertTrue(upserts.contains { $0.type == .player && $0.id == changed.players[0].id.uuidString },
                      "The edited player is an upsert")
        XCTAssertTrue(upserts.contains { $0.type == .team && $0.id == changed.teams.last!.id.uuidString },
                      "The new team is an upsert")
        XCTAssertTrue(deletes.isEmpty)
    }

    func testDiffDetectsDeletions() {
        let snapshot = TestData.snapshot(playerCount: 3)
        let base = SyncRecords.records(from: snapshot)

        var changed = snapshot
        let removed = changed.players.removeFirst()

        let (_, deletes) = SyncRecords.diff(from: base, to: SyncRecords.records(from: changed))
        XCTAssertTrue(deletes.contains { $0.type == .player && $0.id == removed.id.uuidString })
    }

    func testDeleteRemovesTheEntity() {
        var snapshot = TestData.snapshot(playerCount: 2)
        let player = snapshot.players[0]
        SyncRecords.delete(type: .player, id: player.id.uuidString, from: &snapshot)
        XCTAssertFalse(snapshot.players.contains { $0.id == player.id })
    }

    func testUnchangedSnapshotProducesNoDiff() {
        let records = SyncRecords.records(from: TestData.snapshot(playerCount: 2))
        let (upserts, deletes) = SyncRecords.diff(from: records, to: records)
        XCTAssertTrue(upserts.isEmpty)
        XCTAssertTrue(deletes.isEmpty)
    }
}

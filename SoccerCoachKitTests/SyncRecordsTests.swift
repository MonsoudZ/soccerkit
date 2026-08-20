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

    // MARK: - Single-record lookup

    /// `record(from:type:id:)` materializes one CKRecord on demand and must agree
    /// exactly with the bulk `records(from:)` — `diff` compares payload bytes, so
    /// any divergence would surface as a phantom edit uploaded on every sync.
    /// It encodes just the one entity rather than the whole snapshot, and this is
    /// what pins that shortcut to the bulk encoding for every record type.
    func testSingleRecordLookupMatchesBulkEncodingForEveryType() {
        let snapshot = Self.snapshotWithEveryRecordType()
        let all = SyncRecords.records(from: snapshot)

        // Guard the fixture: a newly added SyncRecordType that isn't represented
        // here would otherwise silently go unchecked below.
        XCTAssertEqual(Set(all.map(\.type)), Set(SyncRecordType.allCases),
                       "Fixture must carry one of every record type")

        for expected in all {
            XCTAssertEqual(
                SyncRecords.record(from: snapshot, type: expected.type, id: expected.id),
                expected,
                "Single-record lookup disagrees with the bulk encoding for \(expected.type)"
            )
        }
    }

    func testSingleRecordLookupReturnsNilWhenTheRecordIsAbsent() {
        let snapshot = Self.snapshotWithEveryRecordType()
        XCTAssertNil(SyncRecords.record(from: snapshot, type: .player, id: UUID().uuidString),
                     "An id no entity carries has no record")
        XCTAssertNil(SyncRecords.record(from: snapshot, type: .player, id: "not-a-uuid"),
                     "A malformed id is not a lookup failure to trap on")
        XCTAssertNil(SyncRecords.record(from: snapshot, type: .prefs, id: "not-the-prefs-id"),
                     "Prefs is a singleton under one fixed id")
    }

    /// A snapshot carrying at least one of every syncable entity. Deliberately
    /// hand-built rather than derived from `SampleData`, so adding a record type
    /// forces a decision here instead of quietly reducing coverage.
    private static func snapshotWithEveryRecordType() -> AppSnapshot {
        let team = TestData.team()
        let player = TestData.player(teamID: team.id, number: 7)
        let drill = TestData.drill(teamID: team.id)
        let templateID = UUID()
        let personID = UUID()

        return AppSnapshot(
            teams: [team],
            players: [player],
            drills: [drill],
            sessions: [TrainingSession(
                id: UUID(), teamID: team.id, title: "Session", date: Date(), objective: "Shape",
                blocks: [TrainingBlock(id: UUID(), drillID: drill.id, minutes: 15, focus: "Focus")],
                attendance: [player.id: .present]
            )],
            diagrams: [TacticsDiagram(
                id: UUID(), teamID: team.id, title: "Diagram", notes: "", sessionID: nil,
                players: [], zones: [], lines: [], updatedAt: Date()
            )],
            games: [GameEvent(id: UUID(), teamID: team.id, opponent: "Rivals", date: Date())],
            events: [TeamEvent(id: UUID(), teamID: team.id, title: "Tournament",
                               kind: .tournament, date: Date())],
            selectedTeamID: team.id,
            memberships: [RosterMembership(playerID: player.id, teamID: team.id, status: .active)],
            // `people` is synthesized from `players` by AppSnapshot's init, so a
            // player is enough to guarantee a person record.
            userAccounts: [UserAccount(personID: personID, appleUserID: "apple.001")],
            // `organizations` always contains the personal org (ensured by init).
            orgMemberships: [OrgMembership(personID: personID,
                                           organizationID: Organization.personalID,
                                           roles: [.admin, .coach])],
            shareGrants: [ShareGrant(shareableType: .drill, shareableID: drill.id)],
            formTemplates: [FormTemplate(
                id: templateID, context: .postGame, subjectType: .athlete, name: "Review",
                fields: [FormField(key: "effort", label: "Effort", kind: .scale, position: 0)]
            )],
            formInstances: [FormInstance(
                templateID: templateID, context: .postGame,
                subject: FormSubject(type: .athlete, id: player.id)
            )]
        )
    }
}

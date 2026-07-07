import XCTest
@testable import SoccerCoachKit

/// The RosterMembership seam: migration off the flat `Player.teamID`, and the
/// movement stories the time-bounded join is supposed to make free.
final class RosterMembershipTests: XCTestCase {

    // MARK: - Migration

    func testPlayerNoLongerEncodesTeamID() throws {
        let player = Player(id: UUID(), teamID: UUID(), name: "A", number: 5, position: .midfielder,
                            guardian: "", notes: "")
        let data = try JSONEncoder().encode(player)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNil(object["teamID"], "the retired column is never written back")
        XCTAssertEqual(object["number"] as? Int, 5)
    }

    func testLegacyPlayerJSONDecodesTeamIDAsMigrationSeed() throws {
        let playerID = UUID(), teamID = UUID()
        let json = """
        [{"id":"\(playerID.uuidString)","teamID":"\(teamID.uuidString)","name":"Old",
          "number":9,"position":"MID","guardian":"","notes":""}]
        """.data(using: .utf8)!
        let players = try JSONDecoder().decode([Player].self, from: json)
        XCTAssertEqual(players.first?.legacyTeamID, teamID)

        // A pre-membership snapshot synthesizes an active membership from the seed.
        let snapshot = AppSnapshot(teams: [], players: players, drills: [], sessions: [],
                                   diagrams: [], games: [], events: [], selectedTeamID: teamID)
        XCTAssertEqual(snapshot.memberships.count, 1)
        XCTAssertEqual(snapshot.memberships.first?.playerID, playerID)
        XCTAssertEqual(snapshot.memberships.first?.teamID, teamID)
        XCTAssertTrue(snapshot.memberships.first?.isActive ?? false)
    }

    func testMigrationIsIdempotentWhenMembershipsAlreadyExist() {
        let player = TestData.player(teamID: UUID(), number: 1)
        let existing = RosterMembership(playerID: player.id, teamID: UUID())
        let snapshot = AppSnapshot(teams: [], players: [player], drills: [], sessions: [],
                                   diagrams: [], games: [], events: [], selectedTeamID: UUID(),
                                   memberships: [existing])
        XCTAssertEqual(snapshot.memberships.count, 1, "no duplicate synthesized when one is present")
        XCTAssertEqual(snapshot.memberships.first?.teamID, existing.teamID)
    }

    // MARK: - Movement

    @MainActor
    private func twoTeamStore() -> (AppStore, Team, Team, Player) {
        let teamA = TestData.team()
        let teamB = TestData.team()
        let player = TestData.player(teamID: teamA.id, number: 10)
        let snapshot = AppSnapshot(teams: [teamA, teamB], players: [player], drills: [], sessions: [],
                                   diagrams: [], games: [], events: [], selectedTeamID: teamA.id)
        return (AppStore(snapshot: snapshot, persistence: InMemoryPersistence()), teamA, teamB, player)
    }

    @MainActor
    func testMovePlayerEndsOldMembershipAndOpensNewKeepingHistory() {
        let (store, teamA, teamB, player) = twoTeamStore()
        XCTAssertEqual(store.players(inTeam: teamA.id).map(\.id), [player.id])

        store.movePlayer(player.id, toTeam: teamB.id)

        XCTAssertTrue(store.players(inTeam: teamA.id).isEmpty, "left the old team")
        XCTAssertEqual(store.players(inTeam: teamB.id).map(\.id), [player.id], "joined the new team")
        XCTAssertEqual(store.teamID(ofPlayer: player.id), teamB.id)

        let history = store.memberships(ofPlayer: player.id, includeEnded: true)
        XCTAssertEqual(history.count, 2, "old membership kept as history, not deleted")
        XCTAssertEqual(history.filter { $0.isActive }.count, 1)
        XCTAssertTrue(store.players.contains { $0.id == player.id }, "the player themselves is untouched")
    }

    @MainActor
    func testGuestPlayerCreatesConcurrentMembershipsAndSurvivesTeamDeletion() {
        let (store, teamA, teamB, player) = twoTeamStore()

        store.guestPlayer(player.id, ontoTeam: teamB.id)

        XCTAssertTrue(store.isMember(player.id, ofTeam: teamA.id), "still on their own team")
        XCTAssertTrue(store.isMember(player.id, ofTeam: teamB.id), "and guesting on the other")
        XCTAssertEqual(store.players(inTeam: teamA.id).count, 1)
        XCTAssertEqual(store.players(inTeam: teamB.id).count, 1)

        // Deleting the team they only guest for must not delete the player.
        store.deleteTeam(teamB)
        XCTAssertTrue(store.players.contains { $0.id == player.id }, "play-up kid survives")
        XCTAssertTrue(store.isMember(player.id, ofTeam: teamA.id))
    }

    @MainActor
    func testDeletingTheOnlyTeamRemovesTheNowOrphanedPlayer() {
        // Guarding: a player with no remaining membership is removed on cascade.
        let store = TestData.store()               // one team, several players
        let team = store.selectedTeam
        let victim = store.players(inTeam: team.id).first!
        // A second team so the first can be deleted.
        store.addTeam(name: "Other", ageGroup: .u10, season: "2026")
        store.deleteTeam(team)
        XCTAssertFalse(store.players.contains { $0.id == victim.id }, "orphaned player removed")
        XCTAssertTrue(store.memberships.allSatisfy { $0.teamID != team.id }, "memberships cleaned up")
    }

    @MainActor
    func testAddPlayerOpensAnActiveMembership() {
        let store = TestData.store()
        let team = store.selectedTeamID
        let before = store.players(inTeam: team).count
        store.addPlayer(Player(id: UUID(), name: "New", number: 99, position: .forward,
                               guardian: "", notes: ""), toTeam: team)
        XCTAssertEqual(store.players(inTeam: team).count, before + 1)
    }

    @MainActor
    func testDeletePlayerRemovesTheirMemberships() {
        let (store, _, _, player) = twoTeamStore()
        store.deletePlayer(player)
        XCTAssertTrue(store.memberships.allSatisfy { $0.playerID != player.id })
    }

    // MARK: - Sync

    func testMembershipsSyncAsRecords() {
        let membership = RosterMembership(playerID: UUID(), teamID: UUID(), status: .guest)
        let source = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                 games: [], events: [], selectedTeamID: UUID(), memberships: [membership])
        let records = SyncRecords.records(from: source)
        XCTAssertTrue(records.contains { $0.type == .rosterMembership && $0.id == membership.id.uuidString })

        var target = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                 games: [], events: [], selectedTeamID: source.selectedTeamID)
        for record in records { SyncRecords.apply(record, to: &target) }
        XCTAssertEqual(target.memberships, [membership])
    }
}

import XCTest
@testable import SoccerCoachKit

@MainActor
final class UndoAndOnboardingTests: XCTestCase {
    // MARK: - Undo

    func testUndoRestoresDeletedPlayer() {
        let store = TestData.store(TestData.snapshot(playerCount: 3))
        let player = store.roster.first!

        store.deletePlayer(player)
        XCTAssertFalse(store.roster.contains { $0.id == player.id })
        XCTAssertNotNil(store.undoMessage)

        store.undoLastDelete()
        XCTAssertTrue(store.roster.contains { $0.id == player.id })
        XCTAssertNil(store.undoMessage, "Undo clears the banner")
    }

    func testUndoRestoresCascadingTeamDelete() {
        let teamA = TestData.team()
        let teamB = TestData.team()
        let players = [TestData.player(teamID: teamA.id, number: 1),
                       TestData.player(teamID: teamA.id, number: 2)]
        let snapshot = AppSnapshot(teams: [teamA, teamB], players: players, drills: [],
                                   sessions: [], diagrams: [], games: [], events: [],
                                   selectedTeamID: teamA.id)
        let store = AppStore(snapshot: snapshot, persistence: InMemoryPersistence())

        store.deleteTeam(teamA)
        XCTAssertEqual(store.teams.count, 1)
        XCTAssertTrue(store.players.isEmpty, "Players cascade-deleted with the team")

        store.undoLastDelete()
        XCTAssertEqual(store.teams.count, 2, "The team is restored")
        XCTAssertEqual(store.players.count, 2, "...along with its cascaded players")
    }

    func testUndoIsDismissedByALaterEdit() {
        let store = TestData.store(TestData.snapshot(playerCount: 3))
        let player = store.roster.first!

        store.deletePlayer(player)
        XCTAssertNotNil(store.undoMessage)

        // An unrelated change lands within the undo window.
        store.addTeam(name: "New Team", ageGroup: .u10, season: "2026")
        XCTAssertNil(store.undoMessage, "Undo offer is withdrawn once another change happens")

        store.undoLastDelete() // no-op now
        XCTAssertFalse(store.players.contains { $0.id == player.id })
    }

    func testDismissUndoLeavesDataDeleted() {
        let store = TestData.store(TestData.snapshot(playerCount: 2))
        let player = store.roster.first!

        store.deletePlayer(player)
        store.dismissUndo()

        XCTAssertNil(store.undoMessage)
        XCTAssertFalse(store.roster.contains { $0.id == player.id })
        store.undoLastDelete() // no-op now
        XCTAssertFalse(store.roster.contains { $0.id == player.id })
    }

    // MARK: - Onboarding

    func testStartFreshReplacesEverythingWithOneTeam() {
        let store = TestData.store(TestData.snapshot(playerCount: 5))

        store.startFresh(name: "Falcons", ageGroup: .u12, season: "2026", accent: .blue)

        XCTAssertEqual(store.teams.count, 1)
        XCTAssertEqual(store.teams.first?.name, "Falcons")
        XCTAssertEqual(store.teams.first?.ageGroup, .u12)
        XCTAssertEqual(store.teams.first?.accent, .blue)
        XCTAssertTrue(store.players.isEmpty)
        XCTAssertTrue(store.games.isEmpty)
        XCTAssertEqual(store.selectedTeamID, store.teams.first?.id)
    }

    func testStartFreshBlankNameFallsBack() {
        let store = TestData.store()
        store.startFresh(name: "   ", ageGroup: .u8, season: "2026", accent: .teal)
        XCTAssertEqual(store.teams.first?.name, "My Team")
    }
}

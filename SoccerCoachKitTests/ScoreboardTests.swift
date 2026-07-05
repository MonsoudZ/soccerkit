import XCTest
@testable import SoccerCoachKit

@MainActor
final class ScoreboardTests: XCTestCase {
    private func makeVM() -> (GameDayViewModel, AppStore) {
        let store = TestData.store()
        let vm = GameDayViewModel(now: { 0 })
        vm.reset(with: store)
        return (vm, store)
    }

    func testScoringIncrementsAndClampsAtZero() {
        let (vm, store) = makeVM()

        vm.scoreTeam(1, in: store)
        vm.scoreTeam(1, in: store)
        vm.scoreOpponent(1, in: store)
        XCTAssertEqual(vm.teamScore, 2)
        XCTAssertEqual(vm.opponentScore, 1)

        vm.scoreTeam(-1, in: store)
        XCTAssertEqual(vm.teamScore, 1)

        // Never goes negative.
        vm.scoreOpponent(-1, in: store)
        vm.scoreOpponent(-1, in: store)
        XCTAssertEqual(vm.opponentScore, 0)
    }

    func testResetGameClockClearsScore() {
        let (vm, store) = makeVM()
        vm.scoreTeam(3, in: store)
        vm.scoreOpponent(2, in: store)

        vm.resetGameClock()

        XCTAssertEqual(vm.teamScore, 0)
        XCTAssertEqual(vm.opponentScore, 0)
    }

    func testTeamChangeResetsScoreAndOpponent() {
        let (vm, store) = makeVM()
        vm.scoreTeam(4, in: store)
        vm.opponentName = "Rivals FC"

        vm.reset(with: store)

        XCTAssertEqual(vm.teamScore, 0)
        XCTAssertEqual(vm.opponentScore, 0)
        XCTAssertEqual(vm.opponentName, "Opponent")
        XCTAssertNil(vm.linkedGameID)
    }

    // MARK: - Persisting into the post-game report

    /// A store whose selected team has one scheduled game (no score yet).
    private func makeStoreWithGame() -> (GameDayViewModel, AppStore, UUID) {
        let team = TestData.team()
        let game = GameEvent(id: UUID(), teamID: team.id, opponent: "Rivals", date: Date())
        let snapshot = AppSnapshot(
            teams: [team], players: [], drills: [], sessions: [],
            diagrams: [], games: [game], events: [], selectedTeamID: team.id
        )
        let store = AppStore(snapshot: snapshot, persistence: InMemoryPersistence())
        let vm = GameDayViewModel(now: { 0 })
        vm.reset(with: store)
        return (vm, store, game.id)
    }

    func testLinkingAdoptsOpponentAndPersistsLiveScore() {
        let (vm, store, gameID) = makeStoreWithGame()

        vm.linkGame(gameID, in: store)
        XCTAssertEqual(vm.opponentName, "Rivals")

        vm.scoreTeam(2, in: store)
        vm.scoreOpponent(1, in: store)

        let game = store.games.first { $0.id == gameID }
        XCTAssertEqual(game?.teamScore, 2, "Live score is written into the game")
        XCTAssertEqual(game?.opponentScore, 1)
    }

    func testLinkingSeedsFromAnAlreadyRecordedScore() {
        let (vm, store, gameID) = makeStoreWithGame()
        // Pre-record a score on the game.
        var game = store.games.first { $0.id == gameID }!
        game.teamScore = 3
        game.opponentScore = 2
        store.updateGame(game)

        vm.linkGame(gameID, in: store)

        XCTAssertEqual(vm.teamScore, 3, "Scoreboard continues from the recorded score")
        XCTAssertEqual(vm.opponentScore, 2)
    }

    func testUnlinkedScoringDoesNotTouchAnyGame() {
        let (vm, store, gameID) = makeStoreWithGame()

        vm.scoreTeam(1, in: store)

        XCTAssertNil(store.games.first { $0.id == gameID }?.teamScore,
                     "Scoring while unlinked leaves games untouched")
    }
}

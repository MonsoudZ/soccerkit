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
        let (vm, _) = makeVM()

        vm.scoreTeam(1)
        vm.scoreTeam(1)
        vm.scoreOpponent(1)
        XCTAssertEqual(vm.teamScore, 2)
        XCTAssertEqual(vm.opponentScore, 1)

        vm.scoreTeam(-1)
        XCTAssertEqual(vm.teamScore, 1)

        // Never goes negative.
        vm.scoreOpponent(-1)
        vm.scoreOpponent(-1)
        XCTAssertEqual(vm.opponentScore, 0)
    }

    func testResetGameClockClearsScore() {
        let (vm, _) = makeVM()
        vm.scoreTeam(3)
        vm.scoreOpponent(2)

        vm.resetGameClock()

        XCTAssertEqual(vm.teamScore, 0)
        XCTAssertEqual(vm.opponentScore, 0)
    }

    func testTeamChangeResetsScoreAndOpponent() {
        let (vm, store) = makeVM()
        vm.scoreTeam(4)
        vm.opponentName = "Rivals FC"

        vm.reset(with: store)

        XCTAssertEqual(vm.teamScore, 0)
        XCTAssertEqual(vm.opponentScore, 0)
        XCTAssertEqual(vm.opponentName, "Opponent")
    }
}

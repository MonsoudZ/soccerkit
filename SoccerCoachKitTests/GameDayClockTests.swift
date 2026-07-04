import XCTest
@testable import SoccerCoachKit

/// Exercises the real GameDayViewModel wall-clock timekeeping with an injected
/// controllable clock — the behavior previously checked only with throwaway
/// scripts.
@MainActor
final class GameDayClockTests: XCTestCase {
    private var clock: TestClock!
    private var store: AppStore!
    private var vm: GameDayViewModel!

    override func setUp() {
        super.setUp()
        clock = TestClock()
        store = TestData.store(TestData.snapshot(playerCount: 6, ageGroup: .u6)) // 4 on field
        vm = GameDayViewModel(now: clock.now)
        vm.reset(with: store)
    }

    private var aStarter: UUID { vm.starterIDs.first! }
    private var aBenchPlayer: UUID { vm.benchPlayers.first!.id }

    func testElapsedCatchesUpWithNoTicks() {
        vm.start()
        clock.advance(300) // 5 min elapsed, zero tick() calls (backgrounded/locked)
        XCTAssertEqual(vm.elapsedSeconds, 300)
        XCTAssertEqual(vm.playingSeconds[aStarter], 300)
    }

    func testBenchPlayerAccruesNothing() {
        let bench = aBenchPlayer
        vm.start()
        clock.advance(300)
        XCTAssertEqual(vm.playingSeconds[bench], 0)
    }

    func testPauseFreezesClockAndMinutes() {
        vm.start()
        clock.advance(120)
        vm.pause()
        let elapsed = vm.elapsedSeconds
        let starterMinutes = vm.playingSeconds[aStarter]
        clock.advance(120) // time passes while paused
        XCTAssertEqual(vm.elapsedSeconds, elapsed)
        XCTAssertEqual(vm.playingSeconds[aStarter], starterMinutes)
    }

    func testSubFreezesOutgoingAndAccruesIncoming() {
        vm.start()
        clock.advance(200)
        let out = vm.selectedOutPlayerID! // an available starter
        let inPlayer = vm.selectedInPlayerID! // an available bench player
        vm.recordSelectedSub()
        clock.advance(100)
        XCTAssertEqual(vm.playingSeconds[out], 200, "subbed-out player is frozen at sub time")
        XCTAssertEqual(vm.playingSeconds[inPlayer], 100, "subbed-in player accrues only after coming on")
    }

    func testResetGameClockZeroesAndRestoresLineup() {
        vm.start()
        clock.advance(300)
        vm.resetGameClock()
        XCTAssertEqual(vm.elapsedSeconds, 0)
        XCTAssertEqual(vm.playingSeconds[aStarter], 0)
        XCTAssertFalse(vm.isRunning)
        XCTAssertEqual(vm.starterIDs.count, vm.playersOnField)
    }

    func testPeriodAdvanceAndResetRewindsToSnapshot() {
        vm.start()
        clock.advance(300)
        vm.advancePeriod() // period 2 begins at 300
        let atPeriod2 = vm.elapsedSeconds
        let starterAtP2 = vm.playingSeconds[aStarter]
        vm.start()
        clock.advance(200) // play into period 2
        XCTAssertEqual(vm.elapsedSeconds, atPeriod2 + 200)
        vm.resetPeriodClock()
        XCTAssertEqual(vm.elapsedSeconds, atPeriod2, "clock rewinds to period start")
        XCTAssertEqual(vm.playingSeconds[aStarter], starterAtP2, "minutes rewind to period start")
    }

    func testClockNeverGoesBackward() {
        vm.start()
        clock.advance(100)
        let a = vm.elapsedSeconds
        clock.advance(0) // a monotonic source can't move back
        XCTAssertGreaterThanOrEqual(vm.elapsedSeconds, a)
    }
}

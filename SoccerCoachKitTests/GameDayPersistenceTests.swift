import XCTest
@testable import SoccerCoachKit

/// A live match used to exist only in memory, so an eviction or crash at
/// halftime lost the clock, per-player minutes, sub log, and score outright.
/// These cover the save/restore that makes it survive — a "relaunch" being a
/// second view model built over the same state store.
@MainActor
final class GameDayPersistenceTests: XCTestCase {
    private var clock: TestClock!
    private var wall: Date!
    private var stateStore: InMemoryGameDayStateStore!
    private var store: AppStore!

    override func setUp() {
        super.setUp()
        clock = TestClock()
        wall = Date(timeIntervalSinceReferenceDate: 800_000_000)
        stateStore = InMemoryGameDayStateStore()
        store = TestData.store(TestData.snapshot(playerCount: 6, ageGroup: .u6)) // 4 on field
    }

    /// A view model over the shared state store. Calling it twice models the app
    /// being killed and relaunched: the second one sees only what was persisted.
    private func makeViewModel() -> GameDayViewModel {
        GameDayViewModel(now: clock.now, stateStore: stateStore, wallClock: { self.wall })
    }

    private func startedMatch() -> GameDayViewModel {
        let vm = makeViewModel()
        vm.reset(with: store)
        vm.start()
        return vm
    }

    /// Advances both clocks together, the way real time does.
    private func advance(_ seconds: TimeInterval) {
        clock.advance(seconds)
        wall = wall.addingTimeInterval(seconds)
    }

    // MARK: - Restoring

    func testMatchSurvivesRelaunch() {
        let vm = startedMatch()
        let starter = vm.starterIDs.first!
        let bench = vm.benchPlayers.first!
        advance(600)
        vm.scoreTeam(2, in: store)
        vm.scoreOpponent(1, in: store)
        vm.moveToBench(vm.roster.first { $0.id == starter }!)
        vm.pause()

        let elapsed = vm.elapsedSeconds
        let starterMinutes = vm.playingSeconds[starter]

        let relaunched = makeViewModel()
        relaunched.syncRoster(with: store)

        XCTAssertEqual(relaunched.elapsedSeconds, elapsed, "The game clock survives")
        XCTAssertEqual(relaunched.playingSeconds[starter], starterMinutes, "Playing time survives")
        XCTAssertEqual(relaunched.teamScore, 2)
        XCTAssertEqual(relaunched.opponentScore, 1)
        XCTAssertFalse(relaunched.starterIDs.contains(starter), "The lineup survives")
        XCTAssertFalse(relaunched.isRunning, "A paused match comes back paused")
        XCTAssertEqual(relaunched.playingSeconds[bench.id], 0)
    }

    func testSubLogAndRemindersSurviveRelaunch() {
        let vm = startedMatch()
        vm.recordSelectedSub()
        vm.newReminderMinute = 25
        vm.addReminder()
        advance(60)

        XCTAssertEqual(vm.subLog.count, 1)

        let relaunched = makeViewModel()
        relaunched.syncRoster(with: store)

        XCTAssertEqual(relaunched.subLog.map(\.id), vm.subLog.map(\.id), "The sub log survives")
        XCTAssertEqual(relaunched.reminders.map(\.id), vm.reminders.map(\.id), "Pending reminders survive")
    }

    func testPeriodStateSurvivesRelaunch() {
        let vm = startedMatch()
        advance(1200)
        vm.advancePeriod()   // banks the first period and stops the clock
        vm.start()
        advance(180)         // 3 minutes into the second
        vm.pause()

        XCTAssertEqual(vm.periodSeconds, 180)

        let relaunched = makeViewModel()
        relaunched.syncRoster(with: store)

        XCTAssertEqual(relaunched.currentPeriod, 2)
        XCTAssertEqual(relaunched.elapsedSeconds, 1380, "The game clock is the whole match")
        XCTAssertEqual(relaunched.periodSeconds, 180,
                       "...while the period clock still counts from this period's kickoff")
    }

    /// The path the real app takes: the Game Day view appears and calls
    /// `prepareIfNeeded`, which resets whenever the team changed. Restoring
    /// `teamID` is what makes it recognise the resumed match as this team's and
    /// reconcile it instead of wiping it.
    func testPrepareIfNeededResumesTheRestoredMatchRatherThanResettingIt() {
        let vm = startedMatch()
        advance(600)
        vm.scoreTeam(1, in: store)
        vm.pause()

        let relaunched = makeViewModel()
        relaunched.prepareIfNeeded(with: store)

        XCTAssertEqual(relaunched.elapsedSeconds, 600, "The view appearing must not wipe the resumed match")
        XCTAssertEqual(relaunched.teamScore, 1)
        XCTAssertEqual(relaunched.roster.count, store.roster.count, "...and the roster is reconciled")
    }

    // MARK: - The interval the app was gone

    func testRunningClockCreditsTheTimeTheAppWasGone() {
        let vm = startedMatch()
        let starter = vm.starterIDs.first!
        advance(300)
        let elapsedBefore = vm.elapsedSeconds

        // The app dies here. Five more minutes of the match are played without it.
        advance(300)
        let relaunched = makeViewModel()
        relaunched.syncRoster(with: store)

        XCTAssertTrue(relaunched.isRunning, "A running match comes back running")
        XCTAssertEqual(relaunched.elapsedSeconds, elapsedBefore + 300,
                       "The match kept going while the app was gone")
        XCTAssertEqual(relaunched.playingSeconds[starter], elapsedBefore + 300,
                       "An on-field player is credited for the missed interval")
    }

    func testBenchedAndInjuredPlayersAreNotCreditedForTheMissedInterval() {
        let vm = startedMatch()
        let bench = vm.benchPlayers.first!
        let injured = vm.roster.first { vm.starterIDs.contains($0.id) }!
        vm.setPlayerStatus(injured, .injured)
        advance(600) // the app is gone for all of it

        let relaunched = makeViewModel()
        relaunched.syncRoster(with: store)

        XCTAssertEqual(relaunched.playingSeconds[bench.id], 0, "A bench player accrues nothing")
        XCTAssertEqual(relaunched.playingSeconds[injured.id], 0, "An injured player accrues nothing")
    }

    /// The live clock is monotonic (`mach_continuous_time`), which restarts at
    /// boot — so the restore reads the wall-clock instant instead, then
    /// re-anchors. This is that re-anchoring: the monotonic clock disagreeing
    /// with the wall clock must not corrupt the resumed match.
    func testRestoreSurvivesAMonotonicClockThatRestarted() {
        let vm = startedMatch()
        advance(300)
        let elapsedBefore = vm.elapsedSeconds

        wall = wall.addingTimeInterval(120)  // 2 more minutes of match
        clock.seconds = 0                    // ...across a reboot

        let relaunched = makeViewModel()
        relaunched.syncRoster(with: store)

        XCTAssertEqual(relaunched.elapsedSeconds, elapsedBefore + 120,
                       "Elapsed time comes from the wall clock, not the restarted monotonic one")

        clock.advance(60)
        XCTAssertEqual(relaunched.elapsedSeconds, elapsedBefore + 180,
                       "And the resumed clock keeps running from the new anchor")
    }

    // MARK: - What must not be restored

    func testMatchOlderThanTheStalenessWindowIsDiscarded() {
        let vm = startedMatch()
        advance(600)
        vm.pause()

        wall = wall.addingTimeInterval(GameDayViewModel.staleAfter + 60)

        let relaunched = makeViewModel()

        XCTAssertEqual(relaunched.elapsedSeconds, 0, "Yesterday's match isn't resurrected")
        XCTAssertEqual(relaunched.teamScore, 0)
        XCTAssertNil(stateStore.load(), "...and the stale record is dropped rather than left to rot")
    }

    func testUnstartedLineupIsNotTreatedAsAMatchInProgress() {
        let vm = makeViewModel()
        vm.reset(with: store)          // a lineup, but the clock never started
        vm.moveToBench(vm.roster[0])   // and some fiddling with it

        XCTAssertEqual(stateStore.load()?.hasMatchInProgress, false,
                       "A lineup that never kicked off is not a match to resume")

        let relaunched = makeViewModel()
        XCTAssertEqual(relaunched.elapsedSeconds, 0)
        XCTAssertTrue(relaunched.subLog.isEmpty)
        XCTAssertTrue(relaunched.starterIDs.isEmpty, "Nothing was restored at all")
    }

    func testResettingTheGameClockDropsTheSavedMatch() {
        let vm = startedMatch()
        advance(600)
        vm.scoreTeam(1, in: store)
        vm.resetGameClock()

        XCTAssertNil(stateStore.load(), "An explicitly cleared game isn't waiting to come back")

        let relaunched = makeViewModel()
        relaunched.reset(with: store)
        XCTAssertEqual(relaunched.elapsedSeconds, 0)
        XCTAssertEqual(relaunched.teamScore, 0)
    }

    func testSwitchingTeamDropsTheSavedMatch() {
        let vm = startedMatch()
        advance(600)
        XCTAssertNotNil(stateStore.load())

        // A different team selected means a different game entirely.
        let otherTeam = TestData.team()
        store.teams.append(otherTeam)
        store.selectedTeamID = otherTeam.id
        vm.prepareIfNeeded(with: store)

        XCTAssertEqual(vm.elapsedSeconds, 0, "Switching team starts a fresh game")
        XCTAssertNil(stateStore.load())
    }

    // MARK: - Per-coach partitioning

    func testAMatchDoesNotFollowTheCoachWhoSignedOut() {
        let vm = startedMatch()
        advance(600)
        vm.scoreTeam(3, in: store)

        vm.switchUser(to: "coach.b")
        XCTAssertEqual(vm.elapsedSeconds, 0, "The incoming coach sees no match")
        XCTAssertEqual(vm.teamScore, 0)

        // ...and the first coach's match is still theirs when they come back.
        vm.switchUser(to: nil)
        XCTAssertEqual(vm.teamScore, 3)
        XCTAssertEqual(vm.elapsedSeconds, 600)
    }
}

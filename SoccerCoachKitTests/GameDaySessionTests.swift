import XCTest
@testable import SoccerCoachKit

/// A live match has to survive the process, not just navigation.
///
/// `GameDayViewModel` is held for the app's lifetime, which covers switching
/// sections but not a crash, an eviction while backgrounded, or a force-quit.
/// Before this, any of those lost the clock, the lineup, the sub log and the
/// score outright — mid-match, with no way to reconstruct the minutes played.
@MainActor
final class GameDaySessionTests: XCTestCase {
    private var sessions: InMemoryGameDaySessionStore!
    private var clock: TestClock!
    private var date: TestDate!
    private var store: AppStore!

    override func setUp() {
        super.setUp()
        sessions = InMemoryGameDaySessionStore()
        clock = TestClock()
        date = TestDate()
        store = TestData.store(TestData.snapshot(playerCount: 6, ageGroup: .u6)) // 4 on field
    }

    /// A view model on a fresh process, sharing the store the previous one saved
    /// into — the relaunch.
    private func relaunch() -> GameDayViewModel {
        GameDayViewModel(now: clock.now, date: date.now, sessionStore: sessions)
    }

    private func playing(_ vm: GameDayViewModel, _ id: UUID) -> Int {
        vm.playingSeconds[id] ?? 0
    }

    func testAMatchInProgressSurvivesRelaunch() {
        let first = relaunch()
        first.prepareIfNeeded(with: store)
        first.start()

        clock.advance(600); date.advance(600)
        let out = first.availableStarterPlayers[0].id
        let incoming = first.availableBenchPlayers[0].id
        first.selectedOutPlayerID = out
        first.selectedInPlayerID = incoming
        first.recordSelectedSub()
        first.scoreTeam(1, in: store)

        let elapsed = first.elapsedSeconds
        let benchedMinutes = playing(first, out)

        // The process dies here and a new one comes up a second later.
        date.advance(1); clock.advance(1)
        let second = relaunch()
        second.prepareIfNeeded(with: store)

        XCTAssertEqual(second.subLog.count, 1, "the sub log is the match's record — it must come back")
        XCTAssertEqual(second.subLog.first?.outPlayerID, out)
        XCTAssertEqual(second.teamScore, 1, "the score survives")
        XCTAssertTrue(second.starterIDs.contains(incoming), "the lineup survives")
        XCTAssertFalse(second.starterIDs.contains(out))
        XCTAssertEqual(second.elapsedSeconds, elapsed + 1, "the clock kept running while the app was gone")
        XCTAssertEqual(playing(second, out), benchedMinutes,
                       "a benched player's banked minutes don't move")
        XCTAssertTrue(second.isRunning, "a running match comes back running")
    }

    /// The clock is the point: it must count the outage, not restart from where
    /// the last save happened. Minutes played drive the app's fair-play
    /// warnings, so silently under-counting them is worse than losing them
    /// loudly.
    func testTheClockCountsTheTimeTheAppWasGone() {
        let first = relaunch()
        first.prepareIfNeeded(with: store)
        first.start()
        clock.advance(300); date.advance(300)
        let onField = first.availableStarterPlayers[0].id
        let elapsed = first.elapsedSeconds

        date.advance(120) // two minutes of real time with no app running
        let second = relaunch()
        second.prepareIfNeeded(with: store)

        XCTAssertEqual(second.elapsedSeconds, elapsed + 120)
        XCTAssertEqual(playing(second, onField), elapsed + 120,
                       "a player on the field was playing through the outage")
    }

    /// A paused match has nothing outstanding: the gap is not match time.
    func testAPausedMatchDoesNotAccrueWhileAway() {
        let first = relaunch()
        first.prepareIfNeeded(with: store)
        first.start()
        clock.advance(300); date.advance(300)
        first.pause()
        let elapsed = first.elapsedSeconds

        date.advance(600)
        let second = relaunch()
        second.prepareIfNeeded(with: store)

        XCTAssertEqual(second.elapsedSeconds, elapsed)
        XCTAssertFalse(second.isRunning)
    }

    /// An outage far longer than a match wasn't played: keep everything that
    /// happened, but don't leap the clock forward by hours the team spent off
    /// the pitch.
    func testALongOutageKeepsTheMatchButNotTheMissingHours() {
        let first = relaunch()
        first.prepareIfNeeded(with: store)
        first.start()
        clock.advance(600); date.advance(600)
        first.scoreTeam(2, in: store)
        let elapsed = first.elapsedSeconds

        date.advance(GameDayViewModel.maxResumableGap + 60)
        let second = relaunch()
        second.prepareIfNeeded(with: store)

        XCTAssertEqual(second.teamScore, 2, "what happened still happened")
        XCTAssertEqual(second.elapsedSeconds, elapsed, "but the outage isn't match time")
        XCTAssertFalse(second.isRunning, "the coach restarts the clock deliberately")
    }

    /// Yesterday's match is not today's. It's dropped rather than offered.
    func testAMatchFromAnotherDayIsDiscarded() {
        let first = relaunch()
        first.prepareIfNeeded(with: store)
        first.start()
        clock.advance(600); date.advance(600)
        first.scoreTeam(3, in: store)

        date.advance(GameDayViewModel.sessionLifetime + 60)
        let second = relaunch()
        second.prepareIfNeeded(with: store)

        XCTAssertEqual(second.teamScore, 0, "a fresh game, not last night's")
        XCTAssertEqual(second.elapsedSeconds, 0)
        XCTAssertEqual(sessions.clearCount, 1, "the stale match is dropped, not left to rot")
        // What's stored now is the fresh game the restore fell through to, so
        // last night's score is gone from disk as well as from the screen.
        XCTAssertEqual(sessions.load()?.teamScore, 0)
    }

    /// A saved match belongs to the team it was played for.
    func testAMatchIsNotRestoredOntoADifferentTeam() {
        let first = relaunch()
        first.prepareIfNeeded(with: store)
        first.start()
        clock.advance(600); date.advance(600)
        first.scoreTeam(1, in: store)

        store.addTeam(name: "Other", ageGroup: .u10, season: "2026") // also selects it
        let second = relaunch()
        second.prepareIfNeeded(with: store)

        XCTAssertEqual(second.teamScore, 0)
        XCTAssertEqual(second.elapsedSeconds, 0)
    }

    /// Switching coaches must not leave the previous one's match on screen — the
    /// sub log names their players.
    func testSwitchingCoachesDropsTheMatchInMemory() {
        let vm = relaunch()
        vm.prepareIfNeeded(with: store)
        vm.start()
        clock.advance(600); date.advance(600)
        vm.selectedOutPlayerID = vm.availableStarterPlayers[0].id
        vm.selectedInPlayerID = vm.availableBenchPlayers[0].id
        vm.recordSelectedSub()
        vm.scoreTeam(1, in: store)
        XCTAssertFalse(vm.subLog.isEmpty)

        let incoming = InMemoryGameDaySessionStore()
        vm.switchSessionStore(incoming)

        XCTAssertTrue(vm.subLog.isEmpty, "the outgoing coach's subs are gone from memory")
        XCTAssertEqual(vm.teamScore, 0)
        XCTAssertFalse(vm.isRunning)
        XCTAssertNil(incoming.load(),
                     "and the empty match is not written over the incoming coach's saved one")
        XCTAssertNotNil(sessions.load(), "the outgoing coach's match stays under their own key")
    }
}

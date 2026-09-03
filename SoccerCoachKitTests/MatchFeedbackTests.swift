import SwiftUI
import XCTest
@testable import SoccerCoachKit

/// Game-day feedback is driven by `MatchEvent`, not by the match's state, and
/// the reason is entirely in the negative cases: `subLog`, `teamScore` and
/// `currentPeriod` are all set by restoring a saved match, so a view watching
/// them would buzz at a match the coach merely reopened. These pin down both
/// which actions emit and which non-actions must not.
@MainActor
final class MatchFeedbackTests: XCTestCase {

    private func makeStore(playerCount: Int = 8) -> AppStore {
        AppStore(snapshot: TestData.snapshot(playerCount: playerCount),
                 persistence: InMemoryPersistence())
    }

    private func makeMatch(_ store: AppStore) -> GameDayViewModel {
        let viewModel = GameDayViewModel()
        viewModel.prepareIfNeeded(with: store)
        return viewModel
    }

    // MARK: - The clock

    func testStartingAndPausingTheClockEmit() {
        let store = makeStore()
        let match = makeMatch(store)
        XCTAssertNil(match.lastEvent, "a match nobody has touched has nothing to report")

        match.start()
        XCTAssertEqual(match.lastEvent?.kind, .clockStarted)

        match.pause()
        XCTAssertEqual(match.lastEvent?.kind, .clockPaused)
    }

    /// `start` and `pause` both no-op when the clock is already in that state.
    /// Nothing happened, so nothing should be reported.
    func testARedundantStartOrPauseEmitsNothing() {
        let store = makeStore()
        let match = makeMatch(store)

        match.start()
        let afterStart = match.lastEvent
        match.start()
        XCTAssertEqual(match.lastEvent, afterStart, "the clock was already running")

        match.pause()
        let afterPause = match.lastEvent
        match.pause()
        XCTAssertEqual(match.lastEvent, afterPause, "the clock was already paused")
    }

    // MARK: - Score

    func testAGoalEmitsForWhicheverSideScored() {
        let store = makeStore()
        let match = makeMatch(store)

        match.scoreTeam(1, in: store)
        XCTAssertEqual(match.lastEvent?.kind, .goalFor)

        match.scoreOpponent(1, in: store)
        XCTAssertEqual(match.lastEvent?.kind, .goalAgainst)
    }

    /// Tapping a score down is a mis-tap being corrected, not a goal, and the
    /// coach should be able to feel the difference.
    func testCorrectingAScoreEmitsItsOwnEvent() {
        let store = makeStore()
        let match = makeMatch(store)
        match.scoreTeam(1, in: store)

        match.scoreTeam(-1, in: store)

        XCTAssertEqual(match.lastEvent?.kind, .scoreCorrected)
    }

    /// The score is clamped at zero, so this tap changes nothing at all.
    func testAClampedScoreTapEmitsNothing() {
        let store = makeStore()
        let match = makeMatch(store)
        let before = match.lastEvent

        match.scoreTeam(-1, in: store)

        XCTAssertEqual(match.teamScore, 0)
        XCTAssertEqual(match.lastEvent, before, "nothing moved, so nothing happened")
    }

    // MARK: - Substitutions

    func testASubstitutionEmitsOnlyWhenTheSwapHappens() throws {
        let store = makeStore()
        let match = makeMatch(store)
        let onField = try XCTUnwrap(match.starterIDs.first)
        let onBench = try XCTUnwrap(match.roster.first { !match.starterIDs.contains($0.id) })

        match.selectedOutPlayerID = onField
        match.selectedInPlayerID = onBench.id
        match.recordSelectedSub()
        XCTAssertEqual(match.lastEvent?.kind, .subRecorded)

        match.undoLastSub()
        XCTAssertEqual(match.lastEvent?.kind, .subUndone)
    }

    /// `substitute` declines a swap whose outgoing player isn't on the field.
    /// The tap looked the same to the coach, so the silence is the only way
    /// they can tell it didn't take.
    func testARejectedSubstitutionEmitsNothing() throws {
        let store = makeStore()
        let match = makeMatch(store)
        let benchA = try XCTUnwrap(match.roster.first { !match.starterIDs.contains($0.id) })
        let benchB = try XCTUnwrap(match.roster.last { !match.starterIDs.contains($0.id) })
        try XCTSkipIf(benchA.id == benchB.id, "needs two benched players")
        let before = match.lastEvent

        // Neither is on the field, so there is nothing to substitute out.
        match.selectedOutPlayerID = benchA.id
        match.selectedInPlayerID = benchB.id
        match.recordSelectedSub()

        XCTAssertEqual(match.lastEvent, before)
    }

    // MARK: - Restores must stay silent

    /// The whole reason this is an event and not a state observation: a match
    /// read back off disk carries a sub log, a score and a period, and none of
    /// them are things the coach just did.
    func testRestoringASavedMatchEmitsNothing() throws {
        let store = makeStore()
        let sessions = InMemoryGameDaySessionStore()
        let first = GameDayViewModel(sessionStore: sessions)
        first.prepareIfNeeded(with: store)
        let onField = try XCTUnwrap(first.starterIDs.first)
        let onBench = try XCTUnwrap(first.roster.first { !first.starterIDs.contains($0.id) })
        first.start()
        first.scoreTeam(1, in: store)
        first.selectedOutPlayerID = onField
        first.selectedInPlayerID = onBench.id
        first.recordSelectedSub()
        first.persistSession()
        XCTAssertNotNil(sessions.stored, "the match has to actually be on disk for this to mean anything")

        let restored = GameDayViewModel(sessionStore: sessions)
        restored.prepareIfNeeded(with: store)

        XCTAssertEqual(restored.teamScore, 1, "the match really was restored")
        XCTAssertFalse(restored.subLog.isEmpty)
        XCTAssertNil(restored.lastEvent, "reopening a match is not something the coach just did")
    }

    // MARK: - Two of a kind

    /// Two identical actions in a row have to read as two events, or the second
    /// substitution of the half goes unacknowledged.
    func testConsecutiveIdenticalEventsAreDistinct() {
        let store = makeStore()
        let match = makeMatch(store)

        match.scoreTeam(1, in: store)
        let first = match.lastEvent
        match.scoreTeam(1, in: store)

        XCTAssertEqual(match.lastEvent?.kind, first?.kind)
        XCTAssertNotEqual(match.lastEvent, first, "the second goal must register as a change")
    }

    // MARK: - Screen wake

    /// A running clock is what earns an awake screen — not a match that merely
    /// exists, and not one whose app is in the background.
    func testTheScreenStaysAwakeOnlyForARunningClockInTheForeground() {
        XCTAssertTrue(ScreenWake.shouldStayAwake(clockRunning: true, phase: .active))
        XCTAssertFalse(ScreenWake.shouldStayAwake(clockRunning: false, phase: .active),
                       "half time should let the phone sleep")
        XCTAssertFalse(ScreenWake.shouldStayAwake(clockRunning: true, phase: .inactive))
        XCTAssertFalse(ScreenWake.shouldStayAwake(clockRunning: true, phase: .background),
                       "the Live Activity has the lock screen covered")
    }
}

import XCTest
@testable import SoccerCoachKit

/// A save that can't be sealed is dropped rather than written in the clear —
/// the right call for a file holding children's medical notes, but it must not
/// be a silent one. A coach filling in a squad whose changes are only in memory
/// deserves to know before they close the app.
@MainActor
final class SaveStatusTests: XCTestCase {

    func testAFailedWriteIsSurfaced() async {
        let persistence = InMemoryPersistence()
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 2), persistence: persistence)
        XCTAssertEqual(store.saveStatus, .saved, "nothing is wrong yet")

        persistence.failWrites = true
        store.addTeam(name: "Coach A Team", ageGroup: .u12, season: "2026")
        await settle()

        XCTAssertEqual(store.saveStatus, .unsaved,
                       "a change that didn't reach disk must be visible")
    }

    /// It clears itself: the snapshot is retried on the next save and when the
    /// app leaves the foreground, so a Keychain that was briefly unavailable
    /// shouldn't leave a permanent warning.
    func testItClearsOnceWritingWorksAgain() async {
        let persistence = InMemoryPersistence()
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 2), persistence: persistence)

        persistence.failWrites = true
        store.addTeam(name: "First", ageGroup: .u12, season: "2026")
        await settle()
        XCTAssertEqual(store.saveStatus, .unsaved)

        persistence.failWrites = false
        store.addTeam(name: "Second", ageGroup: .u10, season: "2026")
        await settle()
        XCTAssertEqual(store.saveStatus, .saved, "a recovered write clears the warning")
    }

    /// The message has to say something a coach can act on, not just that
    /// something went wrong.
    func testTheWarningExplainsItself() {
        XCTAssertNil(SaveStatus.saved.detail, "no news is no message")
        let detail = SaveStatus.unsaved.detail ?? ""
        XCTAssertTrue(detail.contains("only in memory"), "say what the state is")
        XCTAssertTrue(detail.contains("unlocking"), "say what to do about it")
    }

    /// The status hops to the main actor before it lands, because writes report
    /// from a background queue.
    private func settle() async {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(20))
    }
}

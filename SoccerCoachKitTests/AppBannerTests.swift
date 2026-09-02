import XCTest
@testable import SoccerCoachKit

/// The bottom banner shows at most one thing at a time, so the rule deciding
/// *which* thing is where the behaviour lives. It's a pure function precisely
/// so the precedence and the dismissal rules can be pinned down here.
final class AppBannerTests: XCTestCase {

    private func resolve(
        undo: String? = nil,
        save: SaveStatus = .saved,
        sync: SyncStatus = .off,
        dismissed: String? = nil
    ) -> AppBanner? {
        AppBanner.resolve(undoMessage: undo, saveStatus: save, syncStatus: sync,
                          dismissedSyncMessage: dismissed)
    }

    // MARK: - Nothing to say

    func testQuietWhenNothingIsWrong() {
        XCTAssertNil(resolve())
        XCTAssertNil(resolve(sync: .synced(Date())))
        XCTAssertNil(resolve(sync: .syncing))
    }

    /// Sync being off or unavailable is a configuration state, not a failure.
    /// Settings explains it; nagging about it on every screen would train the
    /// coach to ignore the banner that does matter.
    func testConfigurationStatesDontRaiseABanner() {
        XCTAssertNil(resolve(sync: .off))
        XCTAssertNil(resolve(sync: .unavailable))
    }

    // MARK: - Precedence

    func testUndoOutranksBothWarnings() {
        let banner = resolve(undo: "Deleted Ava Patel", save: .unsaved,
                             sync: .failed("Network unavailable"))
        XCTAssertEqual(banner, .undo("Deleted Ava Patel"),
                       "The undo window closes on its own; the warnings are still true afterwards")
    }

    func testUnsavedOutranksSyncFailure() {
        let banner = resolve(save: .unsaved, sync: .failed("Network unavailable"))
        XCTAssertEqual(banner, .saveFailed,
                       "Lost work beats sync lag")
    }

    func testSyncFailureShowsWhenItIsTheOnlyProblem() {
        XCTAssertEqual(resolve(sync: .failed("Network unavailable")),
                       .syncFailed("Network unavailable"))
    }

    func testUnsavedShowsWhenSyncIsFine() {
        XCTAssertEqual(resolve(save: .unsaved, sync: .synced(Date())), .saveFailed)
    }

    // MARK: - Dismissal

    func testDismissedSyncFailureStaysHidden() {
        XCTAssertNil(resolve(sync: .failed("Network unavailable"),
                             dismissed: "Network unavailable"))
    }

    func testADifferentSyncFailureGetsThroughADismissal() {
        XCTAssertEqual(resolve(sync: .failed("Your session expired"),
                               dismissed: "Network unavailable"),
                       .syncFailed("Your session expired"),
                       "Waving away one failure must not silence an unrelated one")
    }

    /// The modifier clears the dismissal once sync stops failing, so a stale
    /// value can never suppress a later banner. Pinned here so the resolution
    /// side of that contract holds even if the value lingers.
    func testDismissalIsInertWhileSyncIsHealthy() {
        XCTAssertNil(resolve(sync: .synced(Date()), dismissed: "Network unavailable"))
        XCTAssertEqual(resolve(save: .unsaved, sync: .synced(Date()),
                               dismissed: "Network unavailable"),
                       .saveFailed)
    }

    /// A dismissal is per-message, and the save warning has no dismiss control
    /// at all — so it can't be waved away by a sync dismissal leaking across.
    func testSaveWarningIgnoresSyncDismissal() {
        XCTAssertEqual(resolve(save: .unsaved, sync: .failed("Network unavailable"),
                               dismissed: "Network unavailable"),
                       .saveFailed)
    }

    // MARK: - VoiceOver

    func testWarningsAreAnnouncedAndUndoIsNot() {
        XCTAssertNil(AppBanner.undo("Deleted Ava Patel").accessibilityAnnouncement,
                     "The coach just performed the delete; announcing it is noise")

        let save = AppBanner.saveFailed.accessibilityAnnouncement
        XCTAssertEqual(save, "Not saved. \(SaveStatus.unsaved.bannerMessage)")
        XCTAssertTrue(save?.contains("only in memory") == true)

        let sync = AppBanner.syncFailed("Your session expired").accessibilityAnnouncement
        XCTAssertEqual(sync, "Sync error. Your session expired")
    }

    /// The banner reuses the status enums' own label/icon/tint rather than
    /// restating them, so Settings and the banner can't drift apart.
    func testBannerCopyComesFromTheStatusTypes() {
        XCTAssertFalse(SaveStatus.unsaved.bannerMessage.isEmpty)
        XCTAssertTrue(SaveStatus.saved.bannerMessage.isEmpty,
                      "There is no banner for a healthy save, so there is no message for one")
        XCTAssertEqual(SyncStatus.failed("boom").label, "Sync error")
    }
}

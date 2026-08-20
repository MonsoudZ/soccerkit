import XCTest
@testable import SoccerCoachKit

@MainActor
final class AuthTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        UserDefaults(suiteName: "auth.test.\(UUID().uuidString)")!
    }

    func testStartsSignedOut() {
        let auth = AuthController(defaults: isolatedDefaults())
        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.userID)
    }

    func testCompleteSignInPersistsAcrossInstances() {
        let defaults = isolatedDefaults()
        let auth = AuthController(defaults: defaults)

        auth.completeSignIn(userID: "abc123", name: "Alex Coach")
        XCTAssertTrue(auth.isSignedIn)
        XCTAssertEqual(auth.displayName, "Alex Coach")

        let reloaded = AuthController(defaults: defaults)
        XCTAssertEqual(reloaded.userID, "abc123")
        XCTAssertEqual(reloaded.displayName, "Alex Coach")
    }

    func testSignOutClearsEverything() {
        let defaults = isolatedDefaults()
        let auth = AuthController(defaults: defaults)
        auth.completeSignIn(userID: "abc", name: "X")

        auth.signOut()

        XCTAssertFalse(auth.isSignedIn)
        XCTAssertNil(auth.displayName)
        XCTAssertFalse(AuthController(defaults: defaults).isSignedIn)
    }

    func testSubsequentSignInWithoutNameKeepsStoredName() {
        let defaults = isolatedDefaults()
        let auth = AuthController(defaults: defaults)
        auth.completeSignIn(userID: "abc", name: "First Last")

        // Apple only returns the name on the first authorization.
        auth.completeSignIn(userID: "abc", name: nil)

        XCTAssertEqual(auth.displayName, "First Last")
    }
    // MARK: - Guest access

    func testGuestAccessOpensTheAppWithoutAnAccount() {
        let auth = AuthController(defaults: isolatedDefaults())
        XCTAssertFalse(auth.hasAccess, "The gate is closed on first launch")

        auth.continueAsGuest()

        XCTAssertTrue(auth.hasAccess, "The app is usable")
        XCTAssertFalse(auth.isSignedIn, "...but there is still no account")
        XCTAssertNil(auth.userID)
    }

    func testGuestChoiceSurvivesRelaunch() {
        let defaults = isolatedDefaults()
        AuthController(defaults: defaults).continueAsGuest()

        let relaunched = AuthController(defaults: defaults)
        XCTAssertTrue(relaunched.isGuest, "The gate does not come back every launch")
        XCTAssertTrue(relaunched.hasAccess)
    }

    func testSigningInEndsGuestMode() {
        let defaults = isolatedDefaults()
        let auth = AuthController(defaults: defaults)
        auth.continueAsGuest()

        auth.completeSignIn(userID: "abc123", name: "Alex Coach")

        XCTAssertFalse(auth.isGuest, "They have an account now")
        XCTAssertTrue(auth.isSignedIn)
        XCTAssertFalse(AuthController(defaults: defaults).isGuest, "...and that sticks")
    }

    /// Signing out returns to the gate rather than silently dropping them back
    /// into the guest partition, which would show a different set of teams with
    /// no explanation.
    func testSigningOutReturnsToTheGate() {
        let auth = AuthController(defaults: isolatedDefaults())
        auth.continueAsGuest()
        auth.completeSignIn(userID: "abc123", name: nil)

        auth.signOut()

        XCTAssertFalse(auth.hasAccess)
        XCTAssertFalse(auth.isGuest)
    }

    func testContinueAsGuestIsIgnoredOnceSignedIn() {
        let auth = AuthController(defaults: isolatedDefaults())
        auth.completeSignIn(userID: "abc123", name: nil)

        auth.continueAsGuest()

        XCTAssertFalse(auth.isGuest, "An account holder is never also a guest")
        XCTAssertTrue(auth.isSignedIn)
    }

}

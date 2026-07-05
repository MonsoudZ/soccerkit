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
}

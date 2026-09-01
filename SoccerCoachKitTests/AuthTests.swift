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

    /// The backend session is this coach's bearer credential. Leaving it in the
    /// Keychain on sign-out let sync keep talking to the server as them — pushing
    /// the signed-out guest namespace's edits under their identity, and syncing as
    /// the previous coach if a different one signed in on the same device.
    func testSignOutClearsTheBackendSession() {
        let tokens = TokenStore(storage: InMemoryTokenStorage())
        tokens.token = "access"
        tokens.refreshToken = "refresh"
        let auth = AuthController(defaults: isolatedDefaults(), tokens: tokens)
        auth.completeSignIn(userID: "abc", name: "X")

        auth.signOut()

        XCTAssertNil(tokens.token, "sign-out must drop the access token")
        XCTAssertNil(tokens.refreshToken, "sign-out must drop the refresh token")
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

import AuthenticationServices
import XCTest
@testable import SoccerCoachKit

/// The bug these cover: `refreshCredentialState` ran `guard state != .authorized`
/// and signed the coach out on anything else, discarding the `error` argument
/// entirely. A check that merely *failed* reports `.notFound`, so a transient
/// failure was indistinguishable from a deleted credential — and this runs on
/// every launch.
///
/// The cost of getting it wrong grew when sign-out started clearing the backend
/// tokens: a spurious sign-out now drops the coach into the guest namespace (an
/// app that looks empty, because their data is under their own partition) *and*
/// destroys the session, so recovery needs a full Sign in with Apple.
final class CredentialStateTests: XCTestCase {

    private struct CheckFailed: Error {}

    private func shouldSignOut(_ state: ASAuthorizationAppleIDProvider.CredentialState,
                               error: Error? = nil) -> Bool {
        AuthController.shouldSignOut(state: state, error: error)
    }

    // MARK: - The credential is genuinely gone

    func testRevokedEndsTheSession() {
        XCTAssertTrue(shouldSignOut(.revoked))
    }

    func testNotFoundEndsTheSession() {
        XCTAssertTrue(shouldSignOut(.notFound))
    }

    // MARK: - The credential is fine

    func testAuthorizedKeepsTheSession() {
        XCTAssertFalse(shouldSignOut(.authorized))
    }

    /// `.transferred` means the app moved to a different developer team. The
    /// coach is still signed in; the account needs migrating, not ending.
    func testTransferredKeepsTheSession() {
        XCTAssertFalse(shouldSignOut(.transferred))
    }

    // MARK: - The check itself failed

    /// The heart of it: `.notFound` alongside an error is a failed lookup, not a
    /// deleted credential, and the two are indistinguishable from the state
    /// alone. An inconclusive answer must not end the session — the next launch
    /// checks again.
    func testNotFoundWithAnErrorKeepsTheSession() {
        XCTAssertFalse(shouldSignOut(.notFound, error: CheckFailed()),
                       "a failed check must not be read as a deleted credential")
    }

    func testRevokedWithAnErrorKeepsTheSession() {
        XCTAssertFalse(shouldSignOut(.revoked, error: CheckFailed()),
                       "nothing the check reports is trustworthy once it errored")
    }

    /// Every state, paired with an error, has to be inconclusive — otherwise the
    /// error guard is only half-applied.
    func testNoStateEndsTheSessionWhenTheCheckErrored() {
        let states: [ASAuthorizationAppleIDProvider.CredentialState] =
            [.revoked, .authorized, .notFound, .transferred]
        for state in states {
            XCTAssertFalse(shouldSignOut(state, error: CheckFailed()),
                           "state \(state.rawValue) with an error must be inconclusive")
        }
    }
}

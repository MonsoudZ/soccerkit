import XCTest
@testable import SoccerCoachKit

/// Guards the coach-identity reconciliation: the client's derived Person id must
/// match the backend's byte-for-byte, or the account Person and synced Person
/// would drift into two identities.
final class CoachIdentityTests: XCTestCase {

    /// Expected values computed by the Go backend's `uuid.NewSHA1(namespace, sub)`
    /// with the shared namespace 2b6f0cc9-04e9-4c8e-8f1a-7c3d5e2a9b40. If this
    /// fails, the Swift UUIDv5 and Go's have diverged.
    func testCoachIDMatchesBackendUUIDv5() {
        let cases = [
            ("apple-sub-coach", "0007764a-b2f8-588f-8781-64a12338fd7e"),
            ("sub-deterministic", "8f5a6d33-d033-5c55-83a8-5d6fb041936c"),
            ("u123", "ebaacc06-6057-5180-a452-8fa3598a4ca2"),
        ]
        for (sub, expected) in cases {
            XCTAssertEqual(
                Person.coachID(forAppleUserID: sub).uuidString.lowercased(),
                expected,
                "coach id for \(sub) must equal the backend's UUIDv5"
            )
        }
    }

    func testCoachIDIsDeterministic() {
        XCTAssertEqual(Person.coachID(forAppleUserID: "abc"), Person.coachID(forAppleUserID: "abc"))
        XCTAssertNotEqual(Person.coachID(forAppleUserID: "abc"), Person.coachID(forAppleUserID: "xyz"))
    }
}

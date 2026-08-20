import XCTest
@testable import SoccerCoachKit

@MainActor
final class AccountPartitionTests: XCTestCase {
    func testSwitchingUsersIsolatesAndPreservesData() {
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 2),
                             persistence: InMemoryPersistence())

        // The current (guest) coach adds an identifiable team.
        store.addTeam(name: "Coach A Team", ageGroup: .u12, season: "2026")
        XCTAssertTrue(store.teams.contains { $0.name == "Coach A Team" })

        // A different coach signs in — they must not see A's data.
        store.switchUser(to: "userB")
        XCTAssertFalse(store.teams.contains { $0.name == "Coach A Team" },
                       "A different account never sees the previous coach's team")
        store.addTeam(name: "Coach B Team", ageGroup: .u10, season: "2026")

        // Signing out restores the guest partition (A's data is intact).
        store.switchUser(to: nil)
        XCTAssertTrue(store.teams.contains { $0.name == "Coach A Team" })
        XCTAssertFalse(store.teams.contains { $0.name == "Coach B Team" })

        // Coach B signs back in — their data was preserved, not wiped.
        store.switchUser(to: "userB")
        XCTAssertTrue(store.teams.contains { $0.name == "Coach B Team" })
        XCTAssertFalse(store.teams.contains { $0.name == "Coach A Team" })
    }
    /// A guest who builds a roster and then signs in is the same person. Their
    /// work has to follow them into the account — otherwise signing in looks
    /// exactly like losing everything, which is the failure that makes people
    /// never sign in again.
    func testGuestWorkFollowsThemIntoTheirNewAccount() {
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 2),
                             persistence: InMemoryPersistence())
        store.addTeam(name: "Built As Guest", ageGroup: .u12, season: "2026")

        store.switchUser(to: "userA", carryingLocalData: true)

        XCTAssertTrue(store.teams.contains { $0.name == "Built As Guest" },
                      "The roster they built before signing in is still there")
    }

    /// ...but only into an account that has nothing of its own. Signing in on a
    /// second device must not overwrite a real season with whatever was sitting
    /// in that device's signed-out partition.
    func testGuestWorkDoesNotOverwriteAnAccountThatAlreadyHasData() {
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 2),
                             persistence: InMemoryPersistence())

        // The account already has a season on this device.
        store.switchUser(to: "userA")
        store.addTeam(name: "Real Season", ageGroup: .u14, season: "2026")

        // Back to signed-out, where something else gets built.
        store.switchUser(to: nil)
        store.addTeam(name: "Built As Guest", ageGroup: .u12, season: "2026")

        store.switchUser(to: "userA", carryingLocalData: true)

        XCTAssertTrue(store.teams.contains { $0.name == "Real Season" },
                      "The account's own data wins")
        XCTAssertFalse(store.teams.contains { $0.name == "Built As Guest" },
                       "...and is not replaced by the guest partition")
    }

    /// The carry is opt-in precisely so this stays true: a second coach signing
    /// in on a shared device is the same partition transition, and must not
    /// inherit whatever the previous person left in the signed-out partition.
    func testASecondCoachDoesNotInheritTheSignedOutPartition() {
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 2),
                             persistence: InMemoryPersistence())
        store.addTeam(name: "Someone Elses Team", ageGroup: .u12, season: "2026")

        store.switchUser(to: "userB")

        XCTAssertFalse(store.teams.contains { $0.name == "Someone Elses Team" })
    }

}

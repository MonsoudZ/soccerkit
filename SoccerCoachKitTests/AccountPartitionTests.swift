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
}

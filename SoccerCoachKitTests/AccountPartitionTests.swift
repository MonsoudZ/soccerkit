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

    /// A partition swap must not push anything.
    ///
    /// The bug: `switchUser` re-pointed `remoteSync` *after* `restore`, and
    /// `restore` fires a `persist()`. That persist diffed the outgoing coach's
    /// baseline against the incoming coach's snapshot and handed the result to a
    /// service still aimed at the outgoing coach's namespace — so an ordinary
    /// sign-out uploaded the guest partition into the coach's own CloudKit zone
    /// and, because none of their records appear in the incoming snapshot, sent a
    /// tombstone for every one of them. Their synced season was deleted, on this
    /// device and every other one.
    func testSwitchingUsersNeverPushesToTheOutgoingRemote() {
        // A namespace unique to this run, so a watermark banked by another test
        // (or an earlier run) can't shift the diff under us.
        let incoming = "switch-\(UUID().uuidString)"
        let mock = MockRemoteSync()
        let store = AppStore(snapshot: TestData.snapshot(playerCount: 2),
                             persistence: InMemoryPersistence(), remoteSync: mock)
        store.cloudSyncEnabled = true
        store.addTeam(name: "Coach A Team", ageGroup: .u12, season: "2026")
        mock.pushes.removeAll() // only the switch itself is under test

        store.switchUser(to: incoming)

        XCTAssertEqual(mock.pushes.count, 0,
                       "the swap pushed \(mock.pushes.map { $0.namespace }) — nothing may go out while "
                       + "the remote still names the outgoing coach's partition")
        XCTAssertEqual(mock.namespace, incoming, "the remote follows the coach in")

        // And sync isn't left wedged: the next edit still pushes, now to the
        // incoming coach's namespace.
        store.addTeam(name: "Coach B Team", ageGroup: .u10, season: "2026")
        XCTAssertEqual(mock.pushes.last?.namespace, incoming)
        XCTAssertTrue(mock.pushes.allSatisfy { $0.namespace == incoming })
    }
}

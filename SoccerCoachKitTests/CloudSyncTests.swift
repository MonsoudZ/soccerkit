import XCTest
@testable import SoccerCoachKit

/// In-memory stand-in for `NSUbiquitousKeyValueStore`.
private final class FakeKVStore: KeyValueSyncStore {
    var storage: [String: Data] = [:]
    func syncData(forKey key: String) -> Data? { storage[key] }
    func setSyncData(_ data: Data?, forKey key: String) { storage[key] = data }
    @discardableResult func synchronize() -> Bool { true }
}

@MainActor
final class CloudSyncTests: XCTestCase {
    private func snapshot(teamName: String) -> AppSnapshot {
        let team = TestData.team()
        var named = team
        // Team is a struct; rebuild with the given name via a fresh team.
        named = Team(id: team.id, name: teamName, ageGroup: .u10, season: "2026", accentName: "Teal")
        return AppSnapshot(teams: [named], players: [], drills: [], sessions: [],
                           diagrams: [], games: [], events: [], selectedTeamID: named.id)
    }

    func testSaveWritesEncodedSnapshot() {
        let kv = FakeKVStore()
        let sync = CloudSyncService(store: kv, enabled: true)

        sync.save(snapshot(teamName: "Falcons"))

        XCTAssertNotNil(kv.storage[CloudSyncService.key])
    }

    func testDisabledServiceDoesNotWrite() {
        let kv = FakeKVStore()
        let sync = CloudSyncService(store: kv, enabled: false)

        sync.save(snapshot(teamName: "Falcons"))

        XCTAssertNil(kv.storage[CloudSyncService.key])
    }

    func testPullRemoteFiresOnceForNewData() {
        let kv = FakeKVStore()
        let sync = CloudSyncService(store: kv, enabled: true)
        var received: [String] = []
        sync.onRemoteChange = { received.append($0.teams.first?.name ?? "") }

        // Simulate another device having written a snapshot.
        kv.storage[CloudSyncService.key] = try! JSONEncoder().encode(snapshot(teamName: "Rivals"))
        sync.pullRemote()
        sync.pullRemote() // same data — should be ignored (echo)

        XCTAssertEqual(received, ["Rivals"], "Remote change delivered exactly once")
    }

    func testOwnSaveIsNotRedeliveredAsRemote() {
        let kv = FakeKVStore()
        let sync = CloudSyncService(store: kv, enabled: true)
        var received = 0
        sync.onRemoteChange = { _ in received += 1 }

        sync.save(snapshot(teamName: "Falcons"))
        sync.pullRemote() // our own write shouldn't be reported as a remote change

        XCTAssertEqual(received, 0)
    }

    /// End-to-end: a snapshot already present in iCloud is pulled into the store
    /// when it starts, replacing the local data.
    func testRemoteSnapshotUpdatesLiveStore() {
        let kv = FakeKVStore()
        kv.storage[CloudSyncService.key] = try! JSONEncoder().encode(snapshot(teamName: "Remote FC"))
        let sync = CloudSyncService(store: kv, enabled: true)

        let store = AppStore(snapshot: TestData.snapshot(playerCount: 3),
                             persistence: InMemoryPersistence(),
                             cloudSync: sync)

        XCTAssertEqual(store.teams.first?.name, "Remote FC", "Remote snapshot replaced local on launch")
        XCTAssertTrue(store.players.isEmpty, "...including its (empty) roster")
    }
}

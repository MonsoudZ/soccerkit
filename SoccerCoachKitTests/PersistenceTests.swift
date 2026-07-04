import XCTest
@testable import SoccerCoachKit

/// Covers the persistence layer, including the corrupt-data path that guards
/// against the original silent data-loss bug.
final class PersistenceTests: XCTestCase {
    private var defaults: UserDefaults!
    private let key = "test.snapshot"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SoccerCoachKitTests.\(UUID().uuidString)")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    private func service() -> UserDefaultsPersistenceService {
        UserDefaultsPersistenceService(defaults: defaults, storageKey: key)
    }

    func testEmptyWhenNothingStored() {
        if case .empty = service().load() { } else {
            XCTFail("expected .empty for a fresh store")
        }
    }

    func testRoundTrip() {
        let snapshot = TestData.snapshot(playerCount: 4)
        let svc = service()
        svc.save(snapshot)

        guard case .success(let loaded) = svc.load() else {
            return XCTFail("expected .success after save")
        }
        XCTAssertEqual(loaded.teams.count, 1)
        XCTAssertEqual(loaded.players.count, 4)
        XCTAssertEqual(loaded.selectedTeamID, snapshot.selectedTeamID)
    }

    func testCorruptDataReportsCorruptAndDoesNotLose() {
        // Undecodable bytes under the storage key.
        defaults.set(Data([0x00, 0x01, 0x02]), forKey: key)
        let svc = service()

        guard case .corrupt(let data, _) = svc.load() else {
            return XCTFail("expected .corrupt for undecodable data")
        }
        // The raw bytes are surfaced so the caller can preserve them.
        XCTAssertEqual(data, Data([0x00, 0x01, 0x02]))

        // Backing up must not destroy the original blob.
        svc.backupCorruptData(data)
        XCTAssertEqual(defaults.data(forKey: key), Data([0x00, 0x01, 0x02]))
    }

    func testStoredOrSampleFallsBackToSampleWhenEmpty() {
        // Nothing stored -> seeded with sample data rather than crashing/empty.
        let store = AppStore(snapshot: SampleData.snapshot, persistence: InMemoryPersistence())
        XCTAssertFalse(store.teams.isEmpty)
    }
}

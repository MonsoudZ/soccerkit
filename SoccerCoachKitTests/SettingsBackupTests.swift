import XCTest
@testable import SoccerCoachKit

@MainActor
final class SettingsBackupTests: XCTestCase {

    func testExportImportRoundTrip() {
        let store = TestData.store(TestData.snapshot(playerCount: 4))
        let originalTeamID = store.selectedTeamID
        guard let data = store.exportData() else {
            return XCTFail("export produced no data")
        }

        // Import into a different store; it should be fully replaced.
        let other = TestData.store(TestData.snapshot(playerCount: 9))
        XCTAssertTrue(other.importData(data))
        XCTAssertEqual(other.players.count, 4)
        XCTAssertEqual(other.selectedTeamID, originalTeamID)
    }

    func testImportRejectsInvalidData() {
        let store = TestData.store(TestData.snapshot(playerCount: 3))
        XCTAssertFalse(store.importData(Data([0x00, 0x01, 0x02])))
        XCTAssertEqual(store.players.count, 3, "state left untouched on bad import")
    }

    func testImportRejectsEmptySnapshot() {
        let store = TestData.store(TestData.snapshot(playerCount: 3))
        let empty = AppSnapshot(teams: [], players: [], drills: [], sessions: [],
                                diagrams: [], games: [], events: [], selectedTeamID: UUID())
        let data = try! JSONEncoder().encode(empty)
        XCTAssertFalse(store.importData(data))
        XCTAssertEqual(store.teams.count, 1, "empty snapshot rejected, state preserved")
    }

    func testResetToSampleData() {
        let store = TestData.store(TestData.snapshot(playerCount: 2))
        store.resetToSampleData()
        XCTAssertFalse(store.teams.isEmpty)
        XCTAssertGreaterThan(store.players.count, 2) // sample data has more players
    }

    func testCorruptBackupAccess() {
        let persistence = InMemoryPersistence()
        persistence.backupCorruptData(Data([0xDE, 0xAD]))
        let store = AppStore(snapshot: TestData.snapshot(), persistence: persistence)
        XCTAssertTrue(store.hasCorruptBackup)
        XCTAssertEqual(store.corruptBackupData(), Data([0xDE, 0xAD]))
        store.clearCorruptBackup()
        XCTAssertFalse(store.hasCorruptBackup)
    }
}

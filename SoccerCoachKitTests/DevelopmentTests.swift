import XCTest
@testable import SoccerCoachKit

@MainActor
final class DevelopmentTests: XCTestCase {

    func testEntryRatingAccessors() {
        let entry = DevelopmentEntry(date: Date(), notes: "Great effort",
                                     ratings: ["Passing": 4, "Defending": 2])
        XCTAssertEqual(entry.rating(for: .passing), 4)
        XCTAssertEqual(entry.rating(for: .shooting), 0) // unrated
        XCTAssertEqual(entry.ratedSkills, [.passing, .defending]) // canonical order
        XCTAssertFalse(entry.isEmpty)
    }

    func testEntryRoundTrips() throws {
        let entry = DevelopmentEntry(date: Date(), notes: "n", ratings: ["Technical": 5])
        let data = try JSONEncoder().encode(entry)
        // ratings should serialize as a plain JSON object keyed by skill name.
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"Technical\""))
        let decoded = try JSONDecoder().decode(DevelopmentEntry.self, from: data)
        XCTAssertEqual(decoded.rating(for: .technical), 5)
    }

    func testPlayerLegacyDecodeHasEmptyLog() throws {
        let player = TestData.player(teamID: UUID(), number: 5)
        let data = try JSONEncoder().encode(player)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        dict["developmentLog"] = nil
        let legacy = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(Player.self, from: legacy)
        XCTAssertTrue(decoded.developmentLog.isEmpty)
    }

    func testSaveAddsUpdatesAndDeletes() {
        let store = TestData.store(TestData.snapshot(playerCount: 3))
        let player = store.roster.first!

        var entry = DevelopmentEntry(date: Date(), notes: "First look", ratings: ["Passing": 3])
        store.saveDevelopmentEntry(entry, for: player)
        XCTAssertEqual(store.players.first { $0.id == player.id }?.developmentLog.count, 1)

        // Same id => update in place, not a second entry.
        entry.notes = "Updated"
        store.saveDevelopmentEntry(entry, for: player)
        let updated = store.players.first { $0.id == player.id }?.developmentLog
        XCTAssertEqual(updated?.count, 1)
        XCTAssertEqual(updated?.first?.notes, "Updated")

        store.deleteDevelopmentEntry(entry, for: player)
        XCTAssertTrue(store.players.first { $0.id == player.id }?.developmentLog.isEmpty ?? false)
    }
}

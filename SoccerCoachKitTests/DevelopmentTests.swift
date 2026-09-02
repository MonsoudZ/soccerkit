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

    /// The development log is only reachable through the player, and the edit
    /// form doesn't ask about it — so the form must not rebuild the player from
    /// its own fields. It used to, and a coach who corrected a phone number lost
    /// every entry they had recorded (and the deletion synced).
    func testEditingAPlayerKeepsFieldsTheFormDoesNotOwn() {
        let store = TestData.store()
        let player = store.roster[0]
        let personID = player.personID

        store.saveDevelopmentEntry(
            DevelopmentEntry(date: Date(), notes: "Great week", ratings: ["Passing": 4]),
            for: player
        )

        // The coach opens Edit Player and changes only the guardian's phone.
        let stored = store.players.first { $0.id == player.id }!
        let form = PlayerFormViewModel(player: stored)
        form.guardianPhone = "555-0100"
        form.save(into: store)

        let saved = store.players.first { $0.id == player.id }
        XCTAssertEqual(saved?.guardianPhone, "555-0100", "the edit itself applied")
        XCTAssertEqual(saved?.developmentLog.count, 1, "the development log survived the edit")
        XCTAssertEqual(saved?.developmentLog.first?.notes, "Great week")
        XCTAssertEqual(saved?.personID, personID, "the Person link is unchanged")
        XCTAssertEqual(store.person(id: personID)?.guardianPhone, "555-0100",
                       "and the backing Person picked the edit up")
    }

    /// The other half of the same refactor: a brand-new player still starts with
    /// an empty log and a Person link derived from their own id.
    func testAddingAPlayerStartsWithACleanRecord() {
        let store = TestData.store()
        let form = PlayerFormViewModel(player: nil)
        form.name = "  Maya Chen  "
        form.number = 21
        form.allergies = " peanuts "
        form.save(into: store)

        let added = store.roster.first { $0.number == 21 }
        XCTAssertEqual(added?.name, "Maya Chen", "identity fields are trimmed")
        XCTAssertEqual(added?.allergies, "peanuts")
        XCTAssertTrue(added?.developmentLog.isEmpty ?? false)
        XCTAssertEqual(added?.personID, added?.id)
    }
}

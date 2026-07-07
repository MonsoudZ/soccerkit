import XCTest
@testable import SoccerCoachKit

/// The Person/UserAccount seam: a human's identity exists independently of any
/// team or login, is migrated from existing players, and stays in sync as
/// players change — without any view having to read Person yet.
final class PersonSplitTests: XCTestCase {

    // MARK: - Migration

    func testPlayerDecodesDefaultPersonID() throws {
        // A pre-Person blob has no personID; it falls back to the 1:1 default.
        let pid = UUID()
        let json = """
        [{"id":"\(pid.uuidString)","name":"Old","number":9,"position":"MID","guardian":"","notes":""}]
        """.data(using: .utf8)!
        let players = try JSONDecoder().decode([Player].self, from: json)
        XCTAssertEqual(players.first?.personID, pid, "personID defaults to the player id")
    }

    func testSnapshotSynthesizesAPersonPerPlayerWithContactFields() {
        let player = Player(id: UUID(), name: "Maya Chen", number: 2, position: .defender,
                            guardian: "Alex Chen", notes: "", guardianPhone: "555-0142",
                            allergies: "Peanuts", medicalNotes: "Carries an EpiPen")
        let snapshot = AppSnapshot(teams: [], players: [player], drills: [], sessions: [],
                                   diagrams: [], games: [], events: [], selectedTeamID: UUID())
        XCTAssertEqual(snapshot.people.count, 1)
        let person = snapshot.people.first
        XCTAssertEqual(person?.id, player.personID)
        XCTAssertEqual(person?.name, "Maya Chen")
        XCTAssertEqual(person?.guardian, "Alex Chen")
        XCTAssertEqual(person?.guardianPhone, "555-0142")
        XCTAssertEqual(person?.allergies, "Peanuts")
        XCTAssertEqual(person?.medicalNotes, "Carries an EpiPen")
    }

    func testMigrationIsIdempotentWhenPeopleExist() {
        let player = TestData.player(teamID: UUID(), number: 1)
        let existing = Person(id: player.personID, name: "Kept")
        let snapshot = AppSnapshot(teams: [], players: [player], drills: [], sessions: [],
                                   diagrams: [], games: [], events: [], selectedTeamID: UUID(),
                                   people: [existing])
        XCTAssertEqual(snapshot.people.count, 1, "no duplicate Person synthesized")
        XCTAssertEqual(snapshot.people.first?.name, "Kept")
    }

    func testSnapshotWithoutPeopleKeyDecodesAndMigrates() throws {
        let pid = UUID()
        let legacy = """
        {"schemaVersion":1,"dataVersion":1,"teams":[],
         "players":[{"id":"\(pid.uuidString)","name":"Sam","number":3,"position":"FWD","guardian":"G","notes":""}],
         "drills":[],"sessions":[],"diagrams":[],"games":[],"events":[],"selectedTeamID":"\(UUID().uuidString)"}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: legacy)
        XCTAssertEqual(snapshot.people.map(\.id), [pid])
        XCTAssertEqual(snapshot.people.first?.name, "Sam")
        XCTAssertTrue(snapshot.userAccounts.isEmpty)
    }

    func testPlayerStillEncodesItsIdentityFields() throws {
        // The additive step keeps identity on Player (no view churn); confirm it
        // round-trips, now including personID.
        let player = TestData.player(teamID: UUID(), number: 7)
        let data = try JSONEncoder().encode(player)
        let decoded = try JSONDecoder().decode(Player.self, from: data)
        XCTAssertEqual(decoded.personID, player.personID)
        XCTAssertEqual(decoded.guardian, player.guardian)
    }

    // MARK: - Sync

    func testSyncRecordsRoundTripPeopleAndAccounts() {
        let person = Person(id: UUID(), name: "Coach", guardian: "")
        let account = UserAccount(appleUserID: "apple-123", displayName: "Coach")
        let source = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                 games: [], events: [], selectedTeamID: UUID(),
                                 people: [person], userAccounts: [account])
        let records = SyncRecords.records(from: source)
        XCTAssertTrue(records.contains { $0.type == .person && $0.id == person.id.uuidString })
        XCTAssertTrue(records.contains { $0.type == .userAccount && $0.id == account.id.uuidString })

        var target = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                 games: [], events: [], selectedTeamID: source.selectedTeamID)
        for record in records { SyncRecords.apply(record, to: &target) }
        XCTAssertEqual(target.people, [person])
        XCTAssertEqual(target.userAccounts, [account])
    }
}

@MainActor
final class PersonStoreTests: XCTestCase {

    func testEveryPlayerHasASyncedPerson() {
        let store = TestData.store()
        XCTAssertEqual(store.people.count, store.players.count)
        for player in store.players {
            XCTAssertEqual(store.person(for: player)?.name, player.name)
        }
    }

    func testAddPlayerCreatesItsPerson() {
        let store = TestData.store()
        let team = store.selectedTeamID
        let player = Player(id: UUID(), name: "New Kid", number: 99, position: .forward,
                            guardian: "Parent", notes: "", medicalNotes: "None")
        store.addPlayer(player, toTeam: team)
        let person = store.person(for: player)
        XCTAssertEqual(person?.name, "New Kid")
        XCTAssertEqual(person?.guardian, "Parent")
    }

    func testUpdatePlayerKeepsPersonInSync() {
        let store = TestData.store()
        var player = store.players[0]
        player.guardian = "Updated Guardian"
        player.medicalNotes = "New note"
        store.updatePlayer(player)
        XCTAssertEqual(store.person(for: player)?.guardian, "Updated Guardian")
        XCTAssertEqual(store.person(for: player)?.medicalNotes, "New note")
    }

    func testDeletePlayerRemovesTheirPerson() {
        let store = TestData.store()
        let player = store.players[0]
        let personID = player.personID
        store.deletePlayer(player)
        XCTAssertNil(store.person(id: personID))
    }

    func testLinkUserAccountIsIdempotentByAppleID() {
        let store = TestData.store()
        store.linkUserAccount(appleUserID: "apple-abc", displayName: "Coach A")
        store.linkUserAccount(appleUserID: "apple-abc", displayName: "Coach A")
        XCTAssertEqual(store.userAccounts.filter { $0.appleUserID == "apple-abc" }.count, 1)
        XCTAssertNil(store.userAccount(appleUserID: "apple-abc")?.personID, "nullable owner until linked")
    }
}

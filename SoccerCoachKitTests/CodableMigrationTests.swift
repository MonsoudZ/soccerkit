import XCTest
@testable import SoccerCoachKit

/// Confirms new Codable fields decode with migration-safe defaults, so loading
/// data written by an older build never fails or loses information.
final class CodableMigrationTests: XCTestCase {

    /// Encodes `value`, removes `keys` from the JSON, and decodes it back —
    /// simulating data written before those fields existed.
    private func decodeLegacy<T: Codable>(_ value: T, removing keys: [String]) throws -> T {
        let data = try JSONEncoder().encode(value)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in keys { dict[key] = nil }
        let legacy = try JSONSerialization.data(withJSONObject: dict)
        return try JSONDecoder().decode(T.self, from: legacy)
    }

    func testTeamLegacyDefaults() throws {
        let team = TestData.team(ageGroup: .u8, periodFormat: .halves, minMinutes: 5)
        let decoded = try decodeLegacy(team, removing: ["periodFormat", "defaultMinimumMinutes", "trainingDefaults"])
        XCTAssertEqual(decoded.periodFormat, .default(for: .u8))            // quarters for U8
        XCTAssertEqual(decoded.defaultMinimumMinutes, AgeGroup.u8.defaultGameMinutes / 2)
        XCTAssertEqual(decoded.trainingDefaults, .standard)
    }

    func testPlayerLegacyOverrideIsNil() throws {
        let player = TestData.player(teamID: UUID(), number: 7, minOverride: 20)
        let decoded = try decodeLegacy(player, removing: ["minMinutesOverride"])
        XCTAssertNil(decoded.minMinutesOverride)
    }

    func testDrillLegacyIsNotArchived() throws {
        var drill = TestData.drill(teamID: UUID())
        drill.isArchived = true
        let decoded = try decodeLegacy(drill, removing: ["isArchived"])
        XCTAssertFalse(decoded.isArchived)
    }

    func testGameEventLegacyAttendanceEmpty() throws {
        let player = UUID()
        var game = GameEvent(id: UUID(), teamID: UUID(), opponent: "Rivals", date: Date())
        game.attendance[player] = .present
        game.teamScore = 3
        let decoded = try decodeLegacy(game, removing: ["attendance", "teamScore", "opponentScore", "playerReports"])
        XCTAssertTrue(decoded.attendance.isEmpty)
        XCTAssertNil(decoded.teamScore)
        XCTAssertTrue(decoded.playerReports.isEmpty)
    }

    func testSnapshotRoundTrip() throws {
        let snapshot = TestData.snapshot(playerCount: 5)
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: data)
        XCTAssertEqual(decoded.teams.count, snapshot.teams.count)
        XCTAssertEqual(decoded.players.count, snapshot.players.count)
        XCTAssertEqual(decoded.selectedTeamID, snapshot.selectedTeamID)
        XCTAssertEqual(decoded.schemaVersion, AppSnapshot.currentSchemaVersion)
    }
}

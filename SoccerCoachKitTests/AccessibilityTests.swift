import XCTest
@testable import SoccerCoachKit

/// Covers the VoiceOver label strings, which are extracted into pure computed
/// properties so they can be verified without UI tests.
final class AccessibilityTests: XCTestCase {

    func testPositionDisplayName() {
        XCTAssertEqual(PlayerPosition.goalkeeper.displayName, "Goalkeeper")
        XCTAssertEqual(PlayerPosition.midfielder.displayName, "Midfielder")
    }

    func testPlayerLabel() {
        let ava = Player(id: UUID(), teamID: UUID(), name: "Ava Patel", number: 9,
                         position: .forward, guardian: "Dev Patel", notes: "")
        XCTAssertEqual(ava.accessibilityLabel, "Ava Patel, number 9, Forward, guardian Dev Patel")

        let noGuardian = Player(id: UUID(), teamID: UUID(), name: "Sam", number: 3,
                                position: .goalkeeper, guardian: "", notes: "")
        XCTAssertEqual(noGuardian.accessibilityLabel, "Sam, number 3, Goalkeeper")
    }

    func testSeasonStatLabelPluralization() {
        let p = TestData.player(teamID: UUID(), number: 9)
        let stat = PlayerSeasonStats(player: p, goals: 3, assists: 1, gamesPlayed: 2, averageEffort: 4.5)
        let label = stat.accessibilityLabel
        XCTAssertTrue(label.contains("3 goals"))
        XCTAssertTrue(label.contains("1 assist"))       // singular
        XCTAssertTrue(label.contains("2 games played"))
        XCTAssertTrue(label.contains("average effort 4.5 of 5"))
    }

    func testSeasonStatLabelOmitsZeros() {
        let p = TestData.player(teamID: UUID(), number: 1)
        let stat = PlayerSeasonStats(player: p, goals: 1, assists: 0, gamesPlayed: 1, averageEffort: 0)
        let label = stat.accessibilityLabel
        XCTAssertTrue(label.contains("1 goal,"))        // singular
        XCTAssertFalse(label.contains("assist"))        // zero assists omitted
        XCTAssertTrue(label.contains("1 game played"))
        XCTAssertFalse(label.contains("effort"))        // zero effort omitted
    }

    func testDevelopmentEntryLabel() {
        let entry = DevelopmentEntry(date: Date(), notes: "Great scanning",
                                     ratings: ["Passing": 4, "Technical": 3])
        let label = entry.accessibilityLabel
        XCTAssertTrue(label.contains("Technical 3 of 5"))
        XCTAssertTrue(label.contains("Passing 4 of 5"))
        XCTAssertTrue(label.contains("Great scanning"))
    }
}

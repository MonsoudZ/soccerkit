import XCTest
@testable import SoccerCoachKit

final class TeamAccentTests: XCTestCase {

    func testNamedResolvesCaseInsensitively() {
        XCTAssertEqual(TeamAccent.named("blue"), .blue)
        XCTAssertEqual(TeamAccent.named("Blue"), .blue)
        XCTAssertEqual(TeamAccent.named("ORANGE"), .orange)
    }

    func testNamedFallsBackToTeal() {
        XCTAssertEqual(TeamAccent.named("chartreuse"), .teal)
        XCTAssertEqual(TeamAccent.named(""), .teal)
    }

    func testTeamAccentAccessor() {
        let team = Team(id: UUID(), name: "T", ageGroup: .u6, season: "s", accentName: "Purple")
        XCTAssertEqual(team.accent, .purple)

        let legacy = Team(id: UUID(), name: "T", ageGroup: .u6, season: "s", accentName: "Coral")
        XCTAssertEqual(legacy.accent, .teal, "unknown legacy accent degrades to teal")
    }
}

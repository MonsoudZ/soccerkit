import XCTest
@testable import SoccerCoachKit

final class MatchInsightsTests: XCTestCase {
    private let teamID = UUID()
    private let playerID = UUID()

    private func game(
        daysAgo: Int,
        checkIn: PreMatchCheckIn? = nil,
        performance: Int? = nil,
        effort: Int? = nil
    ) -> GameEvent {
        var reflections: [UUID: PostMatchReflection] = [:]
        if let performance { reflections[playerID] = PostMatchReflection(performance: performance) }
        var reports: [UUID: GamePlayerReport] = [:]
        if let effort { reports[playerID] = GamePlayerReport(effort: effort) }
        return GameEvent(
            id: UUID(), teamID: teamID, opponent: "Rivals",
            date: Date(timeIntervalSince1970: TimeInterval(2_000_000 - daysAgo * 86_400)),
            playerReports: reports,
            preMatchCheckIns: checkIn.map { [playerID: $0] } ?? [:],
            postMatchReflections: reflections
        )
    }

    func testReadinessIsMeanOfRatedScales() {
        // sleep 4, energy 2, rest unrated -> mean 3.0
        let checkIn = PreMatchCheckIn(sleep: 4, energy: 2)
        XCTAssertEqual(checkIn.readiness ?? 0, 3.0, accuracy: 0.001)
        XCTAssertNil(PreMatchCheckIn().readiness)
    }

    func testPerformanceRatingPrefersReflectionThenEffort() {
        let g1 = game(daysAgo: 1, performance: 5, effort: 2)
        XCTAssertEqual(MatchInsights.performanceRating(for: playerID, in: g1), 5)
        let g2 = game(daysAgo: 1, effort: 3)
        XCTAssertEqual(MatchInsights.performanceRating(for: playerID, in: g2), 3)
        let g3 = game(daysAgo: 1)
        XCTAssertNil(MatchInsights.performanceRating(for: playerID, in: g3))
    }

    func testTopDifferentiatorIsTheFactorWithTheBiggestGap() {
        let games = [
            // Strong game: great sleep, ok nutrition.
            game(daysAgo: 3, checkIn: PreMatchCheckIn(sleep: 5, nutrition: 4), performance: 5),
            // Weak game: poor sleep, ok nutrition.
            game(daysAgo: 2, checkIn: PreMatchCheckIn(sleep: 2, nutrition: 3), performance: 2),
        ]
        let insight = MatchInsights.insight(for: playerID, games: games)
        XCTAssertTrue(insight.hasComparison)
        XCTAssertEqual(insight.topDifferentiator?.key, "sleep", "sleep gap (3) beats nutrition gap (1)")
        XCTAssertEqual(insight.topDifferentiator?.strongAverage ?? 0, 5, accuracy: 0.001)
        XCTAssertEqual(insight.topDifferentiator?.weakAverage ?? 0, 2, accuracy: 0.001)
    }

    func testNoComparisonWithoutBothStrongAndWeakGames() {
        let games = [
            game(daysAgo: 2, checkIn: PreMatchCheckIn(sleep: 5), performance: 5),
            game(daysAgo: 1, checkIn: PreMatchCheckIn(sleep: 4), performance: 4),
        ]
        let insight = MatchInsights.insight(for: playerID, games: games)
        XCTAssertFalse(insight.hasComparison)
        XCTAssertEqual(insight.gamesWithCheckIn, 2)
        XCTAssertNotNil(insight.averageReadiness)
    }

    func testEmptyCheckInsAreIgnored() {
        let games = [game(daysAgo: 1, checkIn: PreMatchCheckIn(), performance: 5)]
        let insight = MatchInsights.insight(for: playerID, games: games)
        XCTAssertEqual(insight.gamesWithCheckIn, 0)
        XCTAssertNil(insight.averageReadiness)
    }

    func testQuestionnaireFieldsDecodeToEmptyForOlderGames() throws {
        let game = GameEvent(id: UUID(), teamID: teamID, opponent: "R", date: Date())
        let data = try JSONEncoder().encode(game)
        var dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for key in ["preMatchCheckIns", "postMatchReflections", "coachPreMatch", "coachPostMatch"] {
            dict[key] = nil
        }
        let legacy = try JSONSerialization.data(withJSONObject: dict)
        let decoded = try JSONDecoder().decode(GameEvent.self, from: legacy)
        XCTAssertTrue(decoded.preMatchCheckIns.isEmpty)
        XCTAssertTrue(decoded.postMatchReflections.isEmpty)
        XCTAssertTrue(decoded.coachPreMatch.isEmpty)
        XCTAssertTrue(decoded.coachPostMatch.isEmpty)
    }
}

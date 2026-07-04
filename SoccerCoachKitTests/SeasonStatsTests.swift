import XCTest
@testable import SoccerCoachKit

final class SeasonStatsTests: XCTestCase {

    private func game(_ team: UUID, our: Int?, their: Int?) -> GameEvent {
        var g = GameEvent(id: UUID(), teamID: team, opponent: "X", date: Date())
        g.teamScore = our
        g.opponentScore = their
        return g
    }

    func testTeamRecordSkipsUnscoredGames() {
        let t = UUID()
        let games = [
            game(t, our: 3, their: 1),     // win
            game(t, our: 0, their: 2),     // loss
            game(t, our: 1, their: 1),     // draw
            game(t, our: nil, their: nil)  // not played -> skipped
        ]
        let r = SeasonStats.teamRecord(games: games)
        XCTAssertEqual(r.wins, 1)
        XCTAssertEqual(r.losses, 1)
        XCTAssertEqual(r.draws, 1)
        XCTAssertEqual(r.played, 3)
        XCTAssertEqual(r.goalsFor, 4)
        XCTAssertEqual(r.goalsAgainst, 4)
        XCTAssertEqual(r.goalDifference, 0)
        XCTAssertEqual(r.summary, "1-1-1")
    }

    func testPlayerStatsAggregateAndRank() {
        let teamID = UUID()
        let p1 = TestData.player(teamID: teamID, number: 7)
        let p2 = TestData.player(teamID: teamID, number: 10)

        var g1 = GameEvent(id: UUID(), teamID: teamID, opponent: "A", date: Date())
        g1.playerReports[p1.id] = GamePlayerReport(goals: 2, assists: 1, effort: 4)
        g1.playerReports[p2.id] = GamePlayerReport(goals: 0, assists: 2, effort: 5)
        g1.attendance[p1.id] = .present
        g1.attendance[p2.id] = .late

        var g2 = GameEvent(id: UUID(), teamID: teamID, opponent: "B", date: Date())
        g2.playerReports[p1.id] = GamePlayerReport(goals: 1, assists: 0, effort: 2)
        g2.attendance[p1.id] = .present
        g2.attendance[p2.id] = .absent // absent doesn't count toward games played

        let stats = SeasonStats.playerStats(players: [p1, p2], games: [g1, g2])

        // Ranked by contributions: p1 has 3G+1A = 4, p2 has 0G+2A = 2.
        XCTAssertEqual(stats.first?.id, p1.id)

        let s1 = stats.first { $0.id == p1.id }!
        XCTAssertEqual(s1.goals, 3)
        XCTAssertEqual(s1.assists, 1)
        XCTAssertEqual(s1.gamesPlayed, 2)
        XCTAssertEqual(s1.averageEffort, 3.0, accuracy: 0.001) // (4 + 2) / 2

        let s2 = stats.first { $0.id == p2.id }!
        XCTAssertEqual(s2.gamesPlayed, 1, "late counts, absent does not")
        XCTAssertEqual(s2.averageEffort, 5.0, accuracy: 0.001)
    }

    func testEmptyInputs() {
        XCTAssertEqual(SeasonStats.teamRecord(games: []), TeamRecord())
        XCTAssertTrue(SeasonStats.playerStats(players: [], games: []).isEmpty)
    }
}

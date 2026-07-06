import XCTest
@testable import SoccerCoachKit

final class PlayerDevelopmentTests: XCTestCase {
    private let teamID = UUID()

    private func game(
        daysAgo: Int,
        opponent: String = "Rivals",
        attendance: [UUID: AttendanceStatus] = [:],
        reports: [UUID: GamePlayerReport] = [:],
        teamScore: Int? = nil,
        opponentScore: Int? = nil
    ) -> GameEvent {
        GameEvent(id: UUID(), teamID: teamID, opponent: opponent,
                  date: Date(timeIntervalSince1970: TimeInterval(1_000_000 - daysAgo * 86_400)),
                  attendance: attendance, teamScore: teamScore, opponentScore: opponentScore,
                  playerReports: reports)
    }

    func testEmptyWhenNoGamesTouchThePlayer() {
        let player = TestData.player(teamID: teamID, number: 7)
        let profile = PlayerDevelopment.profile(for: player, games: [game(daysAgo: 1)])
        XCTAssertTrue(profile.timeline.isEmpty)
        XCTAssertNil(profile.attendanceRate)
        XCTAssertEqual(profile.contributions, 0)
    }

    func testAggregatesScoringAndEffort() {
        let player = TestData.player(teamID: teamID, number: 9)
        let games = [
            game(daysAgo: 3, attendance: [player.id: .present],
                 reports: [player.id: GamePlayerReport(goals: 2, assists: 1, effort: 4)]),
            game(daysAgo: 2, attendance: [player.id: .present],
                 reports: [player.id: GamePlayerReport(goals: 1, assists: 0, effort: 2)]),
        ]
        let profile = PlayerDevelopment.profile(for: player, games: games)
        XCTAssertEqual(profile.goals, 3)
        XCTAssertEqual(profile.assists, 1)
        XCTAssertEqual(profile.contributions, 4)
        XCTAssertEqual(profile.averageEffort, 3.0, accuracy: 0.001)
    }

    func testAttendanceRateCountsPresentAndLateOverTracked() {
        let player = TestData.player(teamID: teamID, number: 5)
        let games = [
            game(daysAgo: 4, attendance: [player.id: .present]),
            game(daysAgo: 3, attendance: [player.id: .late]),
            game(daysAgo: 2, attendance: [player.id: .absent]),
            game(daysAgo: 1, attendance: [player.id: .excused]),
        ]
        let profile = PlayerDevelopment.profile(for: player, games: games)
        XCTAssertEqual(profile.gamesTracked, 4)
        XCTAssertEqual(profile.gamesAttended, 2, "present + late count as attended")
        XCTAssertEqual(profile.attendanceRate ?? 0, 0.5, accuracy: 0.001)
    }

    func testUnratedEffortIsExcludedFromAverage() {
        let player = TestData.player(teamID: teamID, number: 3)
        let games = [
            game(daysAgo: 2, attendance: [player.id: .present],
                 reports: [player.id: GamePlayerReport(goals: 0, assists: 0, effort: 0)]),
            game(daysAgo: 1, attendance: [player.id: .present],
                 reports: [player.id: GamePlayerReport(goals: 0, assists: 0, effort: 4)]),
        ]
        let profile = PlayerDevelopment.profile(for: player, games: games)
        XCTAssertEqual(profile.averageEffort, 4.0, accuracy: 0.001, "effort 0 means unrated, not a sample")
    }

    func testTimelineIsChronologicalWithOutcomes() {
        let player = TestData.player(teamID: teamID, number: 11)
        let games = [
            game(daysAgo: 1, opponent: "Newest", attendance: [player.id: .present], teamScore: 1, opponentScore: 3),
            game(daysAgo: 3, opponent: "Oldest", attendance: [player.id: .present], teamScore: 2, opponentScore: 0),
            game(daysAgo: 2, opponent: "Middle", attendance: [player.id: .present], teamScore: 1, opponentScore: 1),
        ]
        let profile = PlayerDevelopment.profile(for: player, games: games)
        XCTAssertEqual(profile.timeline.map(\.opponent), ["Oldest", "Middle", "Newest"])
        XCTAssertEqual(profile.timeline.map(\.outcome), [.win, .draw, .loss])
    }

    func testRecentFormKeepsOnlyAttendedGamesMostRecentLast() {
        let player = TestData.player(teamID: teamID, number: 8)
        var games: [GameEvent] = []
        for day in stride(from: 8, through: 1, by: -1) {
            // Miss the game 5 days ago; attend the rest.
            let status: AttendanceStatus = day == 5 ? .absent : .present
            games.append(game(daysAgo: day, opponent: "G\(day)", attendance: [player.id: status]))
        }
        let form = PlayerDevelopment.profile(for: player, games: games).recentForm(3)
        XCTAssertEqual(form.count, 3)
        XCTAssertTrue(form.allSatisfy(\.attended))
        // Most recent three attended games are days 3, 2, 1 -> oldest-first.
        XCTAssertEqual(form.map(\.opponent), ["G3", "G2", "G1"])
    }

    func testReportWithoutAttendanceStillContributesButIsntTracked() {
        let player = TestData.player(teamID: teamID, number: 6)
        let games = [
            game(daysAgo: 1, reports: [player.id: GamePlayerReport(goals: 1, assists: 1, effort: 3)]),
        ]
        let profile = PlayerDevelopment.profile(for: player, games: games)
        XCTAssertEqual(profile.contributions, 2)
        XCTAssertEqual(profile.gamesTracked, 0, "no attendance recorded")
        XCTAssertNil(profile.attendanceRate)
        XCTAssertEqual(profile.timeline.count, 1)
    }
}

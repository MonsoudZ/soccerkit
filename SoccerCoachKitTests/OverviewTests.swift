import XCTest
@testable import SoccerCoachKit

@MainActor
final class OverviewTests: XCTestCase {

    private func store(teams: [Team], players: [Player] = [], games: [GameEvent] = [],
                       drills: [Drill] = []) -> AppStore {
        let snapshot = AppSnapshot(teams: teams, players: players, drills: drills, sessions: [],
                                   diagrams: [], games: games, events: [],
                                   selectedTeamID: teams.first?.id ?? UUID())
        return AppStore(snapshot: snapshot, persistence: InMemoryPersistence())
    }

    func testPerTeamPlayerLookups() {
        let a = TestData.team(), b = TestData.team()
        let s = store(teams: [a, b], players: [
            TestData.player(teamID: a.id, number: 1),
            TestData.player(teamID: a.id, number: 2),
            TestData.player(teamID: b.id, number: 1)
        ])
        XCTAssertEqual(s.players(inTeam: a.id).count, 2)
        XCTAssertEqual(s.players(inTeam: b.id).count, 1)
        XCTAssertEqual(s.players.count, 3, "total spans all teams")
    }

    /// Attendance and RSVP totals belong to the fixture's own team.
    ///
    /// The bug: both summaries counted against `roster`, which is always the
    /// *selected* team. `CoachOverviewView` renders `soonestGame`, which ranges
    /// over every team, so as soon as the soonest fixture belonged to another
    /// team its own players failed the membership filter and the total came from
    /// a squad they aren't in — "0 going of 3" for a game whose whole squad had
    /// replied.
    func testSummariesCountAgainstTheFixturesOwnTeam() {
        let selected = TestData.team(), other = TestData.team()
        let mine = TestData.player(teamID: selected.id, number: 1)
        let theirs = (1...3).map { TestData.player(teamID: other.id, number: $0) }

        var game = GameEvent(id: UUID(), teamID: other.id, opponent: "X",
                             date: Date().addingTimeInterval(3600))
        for player in theirs { game.rsvps[player.id] = .going }
        for player in theirs { game.attendance[player.id] = .present }

        let s = store(teams: [selected, other], players: [mine] + theirs, games: [game])
        XCTAssertEqual(s.selectedTeamID, selected.id, "the other team's fixture is the one under test")

        let rsvp = s.rsvpSummary(for: game)
        XCTAssertEqual(rsvp.going, 3, "every player on the fixture's team replied")
        XCTAssertEqual(rsvp.total, 3, "out of that team's squad, not the selected team's")

        let attendance = s.attendanceSummary(for: game)
        XCTAssertEqual(attendance.present, 3)
        XCTAssertEqual(attendance.total, 3)
    }

    func testSoonestGameAcrossTeamsAndPerTeamNext() {
        let a = TestData.team(), b = TestData.team()
        func game(_ team: UUID, daysFromNow: Int) -> GameEvent {
            GameEvent(id: UUID(), teamID: team, opponent: "X",
                      date: Calendar.current.date(byAdding: .day, value: daysFromNow, to: Date())!)
        }
        let future10 = game(a.id, daysFromNow: 10)
        let future3 = game(b.id, daysFromNow: 3)
        let past = game(a.id, daysFromNow: -5)
        let s = store(teams: [a, b], games: [future10, future3, past])

        XCTAssertEqual(s.soonestGame?.id, future3.id, "earliest upcoming across all teams")
        XCTAssertEqual(s.nextGame(inTeam: a.id)?.id, future10.id, "team A's next skips its past game")
    }

    func testDrillsPerTeamIncludeSharedAndExcludeArchived() {
        let a = TestData.team(), b = TestData.team()
        let shared = TestData.drill(teamID: nil, title: "Shared")
        let aDrill = TestData.drill(teamID: a.id, title: "A only")
        var archived = TestData.drill(teamID: nil, title: "Old")
        archived.isArchived = true
        let s = store(teams: [a, b], drills: [shared, aDrill, archived])

        XCTAssertTrue(s.drills(inTeam: a.id).contains { $0.id == shared.id })
        XCTAssertTrue(s.drills(inTeam: a.id).contains { $0.id == aDrill.id })
        XCTAssertFalse(s.drills(inTeam: b.id).contains { $0.id == aDrill.id }, "other team's drill excluded")
        XCTAssertFalse(s.drills(inTeam: a.id).contains { $0.id == archived.id }, "archived excluded")
    }
}

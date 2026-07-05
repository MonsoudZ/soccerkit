import XCTest
@testable import SoccerCoachKit

@MainActor
final class WidgetPublishTests: XCTestCase {
    override func setUp() {
        super.setUp()
        WidgetSharedStore.save(nil)
    }

    private func store(games: [GameEvent], team: Team) -> AppStore {
        let snapshot = AppSnapshot(
            teams: [team], players: [], drills: [], sessions: [],
            diagrams: [], games: games, events: [], selectedTeamID: team.id
        )
        return AppStore(snapshot: snapshot, persistence: InMemoryPersistence())
    }

    func testPublishesSoonestUpcomingGame() {
        let team = TestData.team()
        let soon = GameEvent(id: UUID(), teamID: team.id, opponent: "Rivals",
                             date: Date(timeIntervalSinceNow: 86_400), location: "Park", isHome: true)
        let later = GameEvent(id: UUID(), teamID: team.id, opponent: "Distant",
                              date: Date(timeIntervalSinceNow: 10 * 86_400), isHome: false)

        _ = store(games: [later, soon], team: team) // init publishes

        let fixture = WidgetSharedStore.load()
        XCTAssertEqual(fixture?.opponent, "Rivals", "The nearest upcoming game wins")
        XCTAssertEqual(fixture?.teamName, "Test FC")
        XCTAssertEqual(fixture?.location, "Park")
        XCTAssertEqual(fixture?.isHome, true)
    }

    func testNoUpcomingGamesPublishesNothing() {
        let team = TestData.team()
        let past = GameEvent(id: UUID(), teamID: team.id, opponent: "Old",
                             date: Date(timeIntervalSinceNow: -10 * 86_400), isHome: true)

        _ = store(games: [past], team: team)

        // soonestGame only considers today-or-later, so nothing is published.
        XCTAssertNil(WidgetSharedStore.load())
    }

    func testUpdatingAGameRepublishes() {
        let team = TestData.team()
        let game = GameEvent(id: UUID(), teamID: team.id, opponent: "Rivals",
                             date: Date(timeIntervalSinceNow: 86_400), isHome: true)
        let store = store(games: [game], team: team)

        var edited = game
        edited.opponent = "Renamed United"
        store.updateGame(edited)

        XCTAssertEqual(WidgetSharedStore.load()?.opponent, "Renamed United")
    }
}

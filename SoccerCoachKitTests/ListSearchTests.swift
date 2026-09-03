import XCTest
@testable import SoccerCoachKit

/// Search only existed on the roster; Games, Training and Drills had filters or
/// nothing at all. These cover the wiring on each list — that the right fields
/// are searched, and that an empty result can tell "nothing matched" apart from
/// "there is nothing here", which are different things to say to a coach.
@MainActor
final class ListSearchTests: XCTestCase {

    // MARK: - Roster

    private func rosterStore() -> AppStore {
        let team = TestData.team()
        let players = [
            Player(id: UUID(), teamID: team.id, name: "Ana Muñoz", number: 9,
                   position: .forward, guardian: "Rosa Muñoz", notes: ""),
            Player(id: UUID(), teamID: team.id, name: "Sam Okafor", number: 3,
                   position: .goalkeeper, guardian: "Ada Okafor", notes: "")
        ]
        return AppStore(snapshot: AppSnapshot(teams: [team], players: players, drills: [],
                                              sessions: [], diagrams: [], games: [], events: [],
                                              selectedTeamID: team.id),
                        persistence: InMemoryPersistence())
    }

    func testRosterSearchFindsAnAccentedNameTypedPlainly() {
        let store = rosterStore()
        let viewModel = RosterViewModel()
        viewModel.searchText = "munoz"

        let found = viewModel.filteredRoster(in: store)

        XCTAssertEqual(found.map(\.name), ["Ana Muñoz"])
    }

    func testRosterSearchStillMatchesNumberAndGuardian() {
        let store = rosterStore()
        let viewModel = RosterViewModel()

        viewModel.searchText = "3"
        XCTAssertEqual(viewModel.filteredRoster(in: store).map(\.name), ["Sam Okafor"])

        viewModel.searchText = "Ada"
        XCTAssertEqual(viewModel.filteredRoster(in: store).map(\.name), ["Sam Okafor"])
    }

    /// The search and the position filter narrow together, not instead of each
    /// other.
    func testRosterSearchAndPositionFilterCombine() {
        let store = rosterStore()
        let viewModel = RosterViewModel()
        viewModel.searchText = "a"           // matches both names
        viewModel.positionFilter = .goalkeeper

        XCTAssertEqual(viewModel.filteredRoster(in: store).map(\.name), ["Sam Okafor"])
        XCTAssertTrue(viewModel.isFiltering)
    }

    // MARK: - Games

    func testGamesSearchMatchesOpponentAndVenue() {
        let team = TestData.team()
        let games = [
            GameEvent(id: UUID(), teamID: team.id, opponent: "Riverside United",
                      date: Date(), location: "Ash Lane", isHome: true, notes: ""),
            GameEvent(id: UUID(), teamID: team.id, opponent: "Hill Rovers",
                      date: Date(), location: "Beech Park", isHome: false, notes: "")
        ]
        let store = AppStore(snapshot: AppSnapshot(teams: [team], players: [], drills: [],
                                                   sessions: [], diagrams: [], games: games,
                                                   events: [], selectedTeamID: team.id),
                             persistence: InMemoryPersistence())
        let viewModel = GamesViewModel()

        viewModel.searchText = "riverside"
        XCTAssertEqual(viewModel.filteredGames(in: store).map(\.opponent), ["Riverside United"])

        viewModel.searchText = "beech"
        XCTAssertEqual(viewModel.filteredGames(in: store).map(\.opponent), ["Hill Rovers"])

        viewModel.searchText = "wanderers"
        XCTAssertTrue(viewModel.filteredGames(in: store).isEmpty)
        XCTAssertTrue(viewModel.isSearching, "so the list says 'no matches', not 'add your first fixture'")
    }

    // MARK: - Training

    /// A coach hunting for "the one with the rondo" is thinking of what was in
    /// the session, not what they named it.
    func testTrainingSearchReachesIntoTheBlocks() {
        let team = TestData.team()
        let drill = TestData.drill(teamID: team.id, title: "Rondo 4v2")
        let sessions = [
            TrainingSession(id: UUID(), teamID: team.id, title: "Tuesday", date: Date(),
                            objective: "Shape",
                            blocks: [TrainingBlock(id: UUID(), drillID: drill.id, minutes: 15,
                                                   focus: "Keep possession", topic: "Rondo")],
                            attendance: [:]),
            TrainingSession(id: UUID(), teamID: team.id, title: "Thursday", date: Date(),
                            objective: "Finishing", blocks: [], attendance: [:])
        ]
        let store = AppStore(snapshot: AppSnapshot(teams: [team], players: [], drills: [drill],
                                                   sessions: sessions, diagrams: [], games: [],
                                                   events: [], selectedTeamID: team.id),
                             persistence: InMemoryPersistence())
        let viewModel = TrainingPlannerViewModel()

        viewModel.searchText = "rondo"
        XCTAssertEqual(viewModel.filteredSessions(in: store).map(\.title), ["Tuesday"])

        viewModel.searchText = "finishing"
        XCTAssertEqual(viewModel.filteredSessions(in: store).map(\.title), ["Thursday"])
    }

    // MARK: - Drills

    func testDrillSearchMatchesTitleAndTags() {
        let team = TestData.team()
        let drills = [
            Drill(id: UUID(), teamID: team.id, title: "Rondo 4v2", category: .technical,
                  tags: ["u12", "possession"], durationMinutes: 15, fieldSetup: "", coachingPoints: []),
            Drill(id: UUID(), teamID: team.id, title: "Shooting Ladder", category: .scrimmage,
                  tags: ["u14"], durationMinutes: 20, fieldSetup: "", coachingPoints: [])
        ]
        let store = AppStore(snapshot: AppSnapshot(teams: [team], players: [], drills: drills,
                                                   sessions: [], diagrams: [], games: [],
                                                   events: [], selectedTeamID: team.id),
                             persistence: InMemoryPersistence())
        let viewModel = DrillLibraryViewModel()

        viewModel.searchText = "possession"
        XCTAssertEqual(viewModel.filteredDrills(in: store).map(\.title), ["Rondo 4v2"])

        // Title and tag together, which no single field holds.
        viewModel.searchText = "u12 rondo"
        XCTAssertEqual(viewModel.filteredDrills(in: store).map(\.title), ["Rondo 4v2"])
    }

    /// The search narrows alongside the category filter rather than replacing
    /// it, and `isFiltering` covers both so the empty state reads correctly.
    func testDrillSearchAndCategoryFilterCombine() {
        let team = TestData.team()
        let drills = [
            Drill(id: UUID(), teamID: team.id, title: "Rondo 4v2", category: .technical,
                  tags: ["u12"], durationMinutes: 15, fieldSetup: "", coachingPoints: []),
            Drill(id: UUID(), teamID: team.id, title: "Rondo Finish", category: .scrimmage,
                  tags: ["u12"], durationMinutes: 15, fieldSetup: "", coachingPoints: [])
        ]
        let store = AppStore(snapshot: AppSnapshot(teams: [team], players: [], drills: drills,
                                                   sessions: [], diagrams: [], games: [],
                                                   events: [], selectedTeamID: team.id),
                             persistence: InMemoryPersistence())
        let viewModel = DrillLibraryViewModel()
        viewModel.searchText = "rondo"
        viewModel.category = .scrimmage

        XCTAssertEqual(viewModel.filteredDrills(in: store).map(\.title), ["Rondo Finish"])
        XCTAssertTrue(viewModel.isFiltering)
    }

    func testAnUntouchedListIsNotReportedAsSearching() {
        XCTAssertFalse(GamesViewModel().isSearching)
        XCTAssertFalse(TrainingPlannerViewModel().isSearching)
        XCTAssertFalse(DrillLibraryViewModel().isFiltering)
        XCTAssertFalse(RosterViewModel().isFiltering)
    }
}

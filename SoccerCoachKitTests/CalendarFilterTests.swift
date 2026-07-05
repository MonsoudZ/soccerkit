import XCTest
@testable import SoccerCoachKit

@MainActor
final class CalendarFilterTests: XCTestCase {
    /// Builds a store whose selected team has a practice and a game on the same
    /// day, and a CalendarViewModel pointed at that day.
    private func makeFixture() -> (AppStore, CalendarViewModel, Date) {
        let team = TestData.team()
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 17))!

        let session = TrainingSession(
            id: UUID(), teamID: team.id, title: "Tuesday Practice", date: day,
            objective: "Passing", blocks: [], attendance: [:]
        )
        let game = GameEvent(
            id: UUID(), teamID: team.id, opponent: "Rivals", date: day, isHome: true
        )

        let snapshot = AppSnapshot(
            teams: [team], players: [], drills: [], sessions: [session],
            diagrams: [], games: [game], events: [], selectedTeamID: team.id
        )
        let store = AppStore(snapshot: snapshot, persistence: InMemoryPersistence())

        let viewModel = CalendarViewModel()
        viewModel.selectedDate = day
        viewModel.displayedMonth = day
        return (store, viewModel, day)
    }

    func testAllKindsEnabledByDefaultShowsEverything() {
        let (store, viewModel, day) = makeFixture()

        XCTAssertFalse(viewModel.isFiltering, "Nothing filtered by default")
        XCTAssertEqual(viewModel.itemsForSelectedDay(in: store).count, 2, "Practice + game both show")
        XCTAssertEqual(Set(viewModel.kinds(on: day, in: store)), [.practice, .game], "Both dots show")
    }

    func testTogglingOffAKindHidesItFromAgendaAndDots() {
        let (store, viewModel, day) = makeFixture()

        viewModel.toggle(.game)

        XCTAssertTrue(viewModel.isFiltering)
        XCTAssertFalse(viewModel.isEnabled(.game))
        XCTAssertTrue(viewModel.isEnabled(.practice))

        let items = viewModel.itemsForSelectedDay(in: store)
        XCTAssertEqual(items.count, 1, "Game is filtered out of the agenda")
        XCTAssertEqual(items.first?.kind, .practice)

        XCTAssertEqual(viewModel.kinds(on: day, in: store), [.practice], "Game dot is filtered out")
    }

    func testTogglingAKindOffThenOnRestoresIt() {
        let (store, viewModel, day) = makeFixture()

        viewModel.toggle(.game)
        viewModel.toggle(.game)

        XCTAssertFalse(viewModel.isFiltering)
        XCTAssertEqual(viewModel.itemsForSelectedDay(in: store).count, 2)
        XCTAssertEqual(Set(viewModel.kinds(on: day, in: store)), [.practice, .game])
    }

    func testShowAllReenablesEveryKind() {
        let (store, viewModel, day) = makeFixture()

        viewModel.toggle(.practice)
        viewModel.toggle(.game)
        XCTAssertTrue(viewModel.itemsForSelectedDay(in: store).isEmpty, "Both hidden")

        viewModel.enableAllKinds()

        XCTAssertFalse(viewModel.isFiltering)
        XCTAssertEqual(viewModel.itemsForSelectedDay(in: store).count, 2, "Show All restores everything")
    }
}

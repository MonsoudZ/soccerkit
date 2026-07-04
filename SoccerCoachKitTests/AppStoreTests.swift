import XCTest
@testable import SoccerCoachKit

/// Covers the store intents and form view models whose invariants were fixed
/// during the audits.
@MainActor
final class AppStoreTests: XCTestCase {

    func testDeleteTeamCascadesAndKeepsSharedDrills() {
        let teamA = TestData.team()
        let teamB = TestData.team()
        let playersA = [TestData.player(teamID: teamA.id, number: 1)]
        let playersB = [TestData.player(teamID: teamB.id, number: 1)]
        let shared = TestData.drill(teamID: nil, title: "Shared")
        let teamADrill = TestData.drill(teamID: teamA.id, title: "A only")

        let snapshot = AppSnapshot(
            teams: [teamA, teamB], players: playersA + playersB,
            drills: [shared, teamADrill], sessions: [], diagrams: [], games: [], events: [],
            selectedTeamID: teamA.id
        )
        let store = AppStore(snapshot: snapshot, persistence: InMemoryPersistence())

        store.deleteTeam(teamA)

        XCTAssertFalse(store.teams.contains { $0.id == teamA.id }, "team removed")
        XCTAssertTrue(store.teams.contains { $0.id == teamB.id }, "other team kept")
        XCTAssertTrue(store.players.allSatisfy { $0.teamID == teamB.id }, "team A players removed")
        XCTAssertTrue(store.drills.contains { $0.id == shared.id }, "shared drill kept")
        XCTAssertFalse(store.drills.contains { $0.id == teamADrill.id }, "team A drill removed")
        XCTAssertEqual(store.selectedTeamID, teamB.id, "reselected surviving team")
    }

    func testLastTeamCannotBeDeleted() {
        let store = TestData.store()
        let only = store.teams[0]
        store.deleteTeam(only)
        XCTAssertEqual(store.teams.count, 1, "the last team is protected")
    }

    func testDeleteDrillArchivesWhenReferencedElseRemoves() {
        let team = TestData.team()
        let usedDrill = TestData.drill(teamID: team.id, title: "Used")
        let unusedDrill = TestData.drill(teamID: team.id, title: "Unused")
        let block = TrainingBlock(id: UUID(), drillID: usedDrill.id, minutes: 10, focus: "F")
        let session = TrainingSession(id: UUID(), teamID: team.id, title: "S", date: Date(),
                                      objective: "O", blocks: [block], attendance: [:])
        let snapshot = AppSnapshot(teams: [team], players: [], drills: [usedDrill, unusedDrill],
                                   sessions: [session], diagrams: [], games: [], events: [],
                                   selectedTeamID: team.id)
        let store = AppStore(snapshot: snapshot, persistence: InMemoryPersistence())

        store.deleteDrill(usedDrill)
        XCTAssertEqual(store.drill(for: usedDrill.id)?.isArchived, true, "referenced drill archived, not removed")
        XCTAssertEqual(store.sessions.first?.blocks.count, 1, "session block preserved")

        store.deleteDrill(unusedDrill)
        XCTAssertNil(store.drill(for: unusedDrill.id), "unreferenced drill removed outright")
    }

    func testTeamEditPreservesMatchRules() {
        let team = TestData.team(ageGroup: .u16, periodFormat: .quarters, minMinutes: 40)
        let snapshot = AppSnapshot(teams: [team], players: [], drills: [], sessions: [],
                                   diagrams: [], games: [], events: [], selectedTeamID: team.id)
        let store = AppStore(snapshot: snapshot, persistence: InMemoryPersistence())

        let vm = TeamFormViewModel(team: team)
        vm.name = "Renamed FC"
        vm.save(into: store)

        let updated = store.teams.first { $0.id == team.id }
        XCTAssertEqual(updated?.name, "Renamed FC")
        XCTAssertEqual(updated?.periodFormat, .quarters, "period format preserved through edit")
        XCTAssertEqual(updated?.defaultMinimumMinutes, 40, "minimum minutes preserved through edit")
    }

    func testJerseyNumberDuplicateDetection() {
        let store = TestData.store(TestData.snapshot(playerCount: 5)) // numbers 1...5
        let existing = store.roster.first { $0.number == 3 }!

        let newVM = PlayerFormViewModel(player: nil)
        newVM.name = "New Kid"
        newVM.number = 3
        XCTAssertTrue(newVM.hasDuplicateNumber(in: store))
        XCTAssertFalse(newVM.canSave(in: store))

        newVM.number = 99
        XCTAssertFalse(newVM.hasDuplicateNumber(in: store))
        XCTAssertTrue(newVM.canSave(in: store))

        // Editing the existing #3 player keeps its own number without flagging.
        let editVM = PlayerFormViewModel(player: existing)
        XCTAssertFalse(editVM.hasDuplicateNumber(in: store))
    }
}

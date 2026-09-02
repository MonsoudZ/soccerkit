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
        XCTAssertTrue(store.players.allSatisfy { store.isMember($0.id, ofTeam: teamB.id) }, "team A players removed")
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

    /// The team form doesn't ask which organization owns the team, so an edit
    /// must not answer for it. Rebuilding the team let `Team.init` default the
    /// owner to the personal org — invisible while that is the only org, and a
    /// team leaving its club as soon as clubs exist.
    func testTeamEditPreservesItsOrganization() {
        let club = UUID()
        let team = Team(id: UUID(), name: "Club FC", ageGroup: .u14, season: "2026",
                        accentName: "Teal", organizationID: club)
        let snapshot = AppSnapshot(teams: [team], players: [], drills: [], sessions: [],
                                   diagrams: [], games: [], events: [], selectedTeamID: team.id)
        let store = AppStore(snapshot: snapshot, persistence: InMemoryPersistence())

        let vm = TeamFormViewModel(team: team)
        vm.name = "Club FC B"
        vm.save(into: store)

        XCTAssertEqual(store.teams.first { $0.id == team.id }?.organizationID, club)
        XCTAssertNotEqual(store.teams.first { $0.id == team.id }?.organizationID,
                          Organization.personalID, "the edit didn't re-home the team")
    }

    /// `Team.ageGroup` resolves a label this build doesn't know to the nearest
    /// band it does, so the form's picker shows U19 for a U21 team. Saving an
    /// unrelated edit must not write that approximation back — sync is
    /// last-write-wins, so it would reach every device.
    func testTeamEditKeepsAnAgeGroupThisBuildDoesNotKnow() throws {
        var dict = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(TestData.team(ageGroup: .u10))) as! [String: Any]
        dict["ageGroup"] = "U21"
        let team = try JSONDecoder().decode(
            Team.self, from: try JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(team.ageGroup, .u19, "precondition: the rulebook falls to the nearest band")

        let snapshot = AppSnapshot(teams: [team], players: [], drills: [], sessions: [],
                                   diagrams: [], games: [], events: [], selectedTeamID: team.id)
        let store = AppStore(snapshot: snapshot, persistence: InMemoryPersistence())

        // The coach fixes a typo in the name and doesn't touch the age picker.
        let vm = TeamFormViewModel(team: team)
        vm.name = "Corrected FC"
        vm.save(into: store)

        let updated = store.teams.first { $0.id == team.id }
        XCTAssertEqual(updated?.name, "Corrected FC")
        XCTAssertEqual(updated?.ageGroupLabel, "U21", "the coach's label survived the edit")
    }

    /// The other half: an age group the coach *does* change is written verbatim,
    /// and the minutes goal is clamped into the new format's game length.
    func testTeamEditWritesAnExplicitAgeGroupChange() {
        let team = TestData.team(ageGroup: .u16, minMinutes: 40)
        let snapshot = AppSnapshot(teams: [team], players: [], drills: [], sessions: [],
                                   diagrams: [], games: [], events: [], selectedTeamID: team.id)
        let store = AppStore(snapshot: snapshot, persistence: InMemoryPersistence())

        let vm = TeamFormViewModel(team: team)
        vm.ageGroup = .u8
        vm.save(into: store)

        let updated = store.teams.first { $0.id == team.id }
        XCTAssertEqual(updated?.ageGroup, .u8)
        XCTAssertEqual(updated?.ageGroupLabel, "U8")
        XCTAssertEqual(updated?.defaultMinimumMinutes, AgeGroup.u8.defaultGameMinutes,
                       "the 40-minute goal was clamped into the shorter game")
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

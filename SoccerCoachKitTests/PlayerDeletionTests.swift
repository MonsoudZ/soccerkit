import XCTest
@testable import SoccerCoachKit

/// The bug these cover: `deletePlayer` cleared a game's `rsvps`, `attendance`,
/// and `playerReports` by hand, so when the questionnaires feature added
/// `preMatchCheckIns` and `postMatchReflections` the cascade wasn't extended.
/// A deleted player's wellness answers — sleep, mood, `hasPain`, `hadInjury` —
/// survived on every game they were recorded in, went out in `exportData()`, and
/// synced to the remote. The most sensitive data the app holds about a minor was
/// the one part a deletion didn't reach.
@MainActor
final class PlayerDeletionTests: XCTestCase {

    /// A store whose first game holds every kind of per-player record for the
    /// player about to be deleted, plus a teammate who must be left alone.
    private func makeStore() -> (AppStore, Player, Player) {
        let store = TestData.store()
        let doomed = store.players[0]
        let teammate = store.players[1]
        store.addGame(opponent: "Rovers", date: Date(), location: "Pitch 3", isHome: true, notes: "")
        var game = store.games[0]
        for player in [doomed, teammate] {
            game.rsvps[player.id] = .going
            game.attendance[player.id] = .present
            game.playerReports[player.id] = GamePlayerReport(minutes: 40, goals: 1, assists: 0,
                                                             effort: 4, developmentFocus: "hold width")
            game.preMatchCheckIns[player.id] = PreMatchCheckIn(sleep: 4, energy: 4, freshness: 3,
                                                               hydration: 4, nutrition: 4, mood: 5,
                                                               composure: 4, focus: 4,
                                                               warmedUp: true, hasPain: true)
            game.postMatchReflections[player.id] = PostMatchReflection(exertion: 4, performance: 4,
                                                                       enjoyment: 5, fatigue: 4,
                                                                       confidence: 4, hadInjury: true)
        }
        store.updateGame(game)
        return (store, doomed, teammate)
    }

    /// The headline fix: the check-ins and reflections go with the player.
    func testDeletingPlayerRemovesTheirCheckInsAndReflections() {
        let (store, doomed, _) = makeStore()
        XCTAssertNotNil(store.games[0].preMatchCheckIns[doomed.id], "fixture must have something to delete")

        store.deletePlayer(doomed)

        XCTAssertNil(store.games[0].preMatchCheckIns[doomed.id],
                     "a deleted player's pre-match check-in must not survive")
        XCTAssertNil(store.games[0].postMatchReflections[doomed.id],
                     "a deleted player's post-match reflection must not survive")
    }

    /// The forget-proof guard. Walks every `[UUID: _]` dictionary on the game by
    /// reflection, so a sixth per-player dictionary added later fails this test
    /// until `removingPlayer` handles it too — which is exactly how the check-ins
    /// were missed in the first place.
    func testNoPerPlayerRecordOnAnyGameSurvivesDeletion() {
        let (store, doomed, _) = makeStore()

        store.deletePlayer(doomed)

        for game in store.games {
            for child in Mirror(reflecting: game).children {
                guard let keyed = child.value as? [UUID: Any] else { continue }
                XCTAssertNil(keyed[doomed.id],
                             "GameEvent.\(child.label ?? "?") still holds the deleted player")
            }
        }
    }

    /// The fixture would pass the reflection sweep trivially if nothing were
    /// keyed by player id, so prove the sweep actually inspects the dictionaries
    /// the fix is about.
    func testTheReflectionSweepSeesThePerPlayerDictionaries() {
        let (store, _, teammate) = makeStore()
        let labels = Mirror(reflecting: store.games[0]).children.compactMap { child -> String? in
            guard let keyed = child.value as? [UUID: Any], keyed[teammate.id] != nil else { return nil }
            return child.label
        }
        XCTAssertEqual(Set(labels), ["rsvps", "attendance", "playerReports",
                                     "preMatchCheckIns", "postMatchReflections"])
    }

    /// Deleting one player must not touch anyone else's records.
    func testTeammateRecordsAreUntouched() {
        let (store, doomed, teammate) = makeStore()

        store.deletePlayer(doomed)

        let game = store.games[0]
        XCTAssertNotNil(game.preMatchCheckIns[teammate.id])
        XCTAssertNotNil(game.postMatchReflections[teammate.id])
        XCTAssertNotNil(game.playerReports[teammate.id])
        XCTAssertNotNil(game.rsvps[teammate.id])
        XCTAssertNotNil(game.attendance[teammate.id])
    }

    /// The delete is undoable as a whole, so an accidental tap restores the
    /// questionnaire answers along with the player.
    func testUndoRestoresTheCheckIns() {
        let (store, doomed, _) = makeStore()
        store.deletePlayer(doomed)

        store.undoLastDelete()

        XCTAssertTrue(store.players.contains { $0.id == doomed.id })
        XCTAssertNotNil(store.games[0].preMatchCheckIns[doomed.id])
        XCTAssertNotNil(store.games[0].postMatchReflections[doomed.id])
    }
}

/// Deleting a team removes the players it leaves with nowhere to play. Those
/// players stop existing, so every reference to them has to go too — the sweep
/// `deletePlayer` has always done, which this path skipped.
@MainActor
final class TeamDeletionSweepTests: XCTestCase {

    func testDeletingATeamClearsItsOrphansFromSurvivingFixtures() {
        let store = TestData.store(TestData.snapshot(playerCount: 2))
        let doomedTeam = store.selectedTeam
        let orphan = store.roster[0]

        // A second team that survives, with a fixture the orphan appears in —
        // a guest appearance recorded before their own team was deleted.
        store.addTeam(name: "Survivors", ageGroup: .u10, season: "2026")
        let survivingTeam = store.selectedTeamID
        store.addGame(opponent: "Rivals", date: Date(), location: "", isHome: true, notes: "")
        store.addSession(title: "Joint session", date: Date(), objective: "")
        let game = store.games.first { $0.teamID == survivingTeam }!
        let session = store.sessions.first { $0.teamID == survivingTeam }!
        store.setAttendance(.present, for: orphan, in: game)
        store.setRSVP(.going, for: orphan, in: session)

        // A diagram on the surviving team with a marker linked to the orphan.
        let diagram = store.addDiagram(title: "Shape")
        var withMarker = store.diagrams.first { $0.id == diagram.id }!
        withMarker.players = [BoardPlayer(id: UUID(), playerID: orphan.id, label: "O",
                                          number: 9, side: .team, position: .zero)]
        store.updateDiagram(withMarker)

        store.deleteTeam(doomedTeam)

        XCTAssertFalse(store.players.contains { $0.id == orphan.id }, "precondition: the orphan is gone")
        XCTAssertNil(store.games.first { $0.id == game.id }?.attendance[orphan.id],
                     "attendance for a deleted player must not survive on another team's game")
        XCTAssertNil(store.sessions.first { $0.id == session.id }?.rsvps[orphan.id],
                     "nor their RSVP on another team's session")
        XCTAssertEqual(store.diagrams.first { $0.id == diagram.id }?.players.first?.playerID, nil,
                       "and a board marker must not keep a dangling player reference")
    }

    /// A player guesting elsewhere isn't orphaned, so nothing of theirs is swept.
    func testAGuestKeepsTheirRecordWhenTheirOtherTeamGoes() {
        let store = TestData.store(TestData.snapshot(playerCount: 2))
        let doomedTeam = store.selectedTeam
        let guest = store.roster[0]

        store.addTeam(name: "Plays Up", ageGroup: .u12, season: "2026")
        let other = store.selectedTeamID
        store.guestPlayer(guest.id, ontoTeam: other)
        store.addGame(opponent: "Rivals", date: Date(), location: "", isHome: true, notes: "")
        let game = store.games.first { $0.teamID == other }!
        store.setAttendance(.present, for: guest, in: game)

        store.deleteTeam(doomedTeam)

        XCTAssertTrue(store.players.contains { $0.id == guest.id }, "a play-up kid survives")
        XCTAssertEqual(store.games.first { $0.id == game.id }?.attendance[guest.id], .present,
                       "and keeps the record they earned on the team they're still on")
    }
}

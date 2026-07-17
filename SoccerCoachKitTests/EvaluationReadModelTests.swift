import XCTest
@testable import SoccerCoachKit

/// The read side of the engine: it must aggregate *every* source of evaluation
/// data — game-day dictionaries still on `GameEvent` plus engine instances —
/// through one query shape, and compute the same readiness the structs do.
final class EvaluationReadModelTests: XCTestCase {

    private func player(_ team: UUID, _ n: Int, dev: [DevelopmentEntry] = []) -> Player {
        Player(id: UUID(), teamID: team, name: "P\(n)", number: n, position: .midfielder,
               guardian: "", notes: "", developmentLog: dev)
    }

    func testProjectionUnifiesLegacyAndCustomStoredButNotBuiltInDuplicates() {
        let team = UUID()
        let p = player(team, 1, dev: [DevelopmentEntry(notes: "note", ratings: ["Passing": 4])])
        let game = GameEvent(
            id: UUID(), teamID: team, opponent: "Rivals", date: Date(),
            playerReports: [p.id: GamePlayerReport(minutes: 60, effort: 4)],
            preMatchCheckIns: [p.id: PreMatchCheckIn(sleep: 4, energy: 4)]
        )
        let customTemplateID = UUID() // not one of the built-ins
        let stored = [
            // A custom-template instance — unified with the legacy sources.
            FormInstance(templateID: customTemplateID, context: .development,
                         subject: .athlete(p.id), answers: [.scale("Tactical", 3)]),
            // A built-in duplicate of the game-day check-in — the legacy dictionary
            // is authoritative, so this must NOT be counted a second time.
            FormInstance(templateID: FormTemplateCatalog.ID.preMatchCheckIn, context: .preGame,
                         subject: .athlete(p.id), answers: [.scale("sleep", 5)]),
        ]

        let instances = EvaluationReadModel.athleteInstances(
            playerID: p.id, developmentLog: p.developmentLog, games: [game], stored: stored)

        // custom stored + (pre-match + report from the game) + 1 development entry = 4.
        // The built-in stored pre-match check-in is dropped (legacy owns it).
        XCTAssertEqual(instances.count, 4)
        XCTAssertEqual(instances.filter { $0.context == .preGame }.count, 1,
                       "only the legacy check-in counts, not the stored built-in duplicate")
        XCTAssertEqual(instances.filter { $0.context == .development }.count, 2, "custom stored + legacy log")
    }

    func testReadinessTrendMatchesCheckInReadinessOldestFirst() {
        let team = UUID()
        let p = player(team, 1)
        let older = GameEvent(id: UUID(), teamID: team, opponent: "A", date: Date().addingTimeInterval(-1000),
                              preMatchCheckIns: [p.id: PreMatchCheckIn(sleep: 2, energy: 2)])
        let newer = GameEvent(id: UUID(), teamID: team, opponent: "B", date: Date(),
                              preMatchCheckIns: [p.id: PreMatchCheckIn(sleep: 5, energy: 5)])

        let instances = EvaluationReadModel.athleteInstances(
            playerID: p.id, developmentLog: [], games: [newer, older], stored: [])
        let trend = EvaluationReadModel.readinessTrend(instances)

        XCTAssertEqual(trend.map(\.value), [2.0, 5.0], "oldest first, each equals the check-in mean")
        XCTAssertEqual(EvaluationReadModel.averageReadiness(instances)!, 3.5, accuracy: 0.0001)
    }

    func testEffortTrendReadsGameReports() {
        let team = UUID()
        let p = player(team, 1)
        let g1 = GameEvent(id: UUID(), teamID: team, opponent: "A", date: Date().addingTimeInterval(-500),
                           playerReports: [p.id: GamePlayerReport(minutes: 50, effort: 3)])
        let g2 = GameEvent(id: UUID(), teamID: team, opponent: "B", date: Date(),
                           playerReports: [p.id: GamePlayerReport(minutes: 55, effort: 5)])

        let instances = EvaluationReadModel.athleteInstances(
            playerID: p.id, developmentLog: [], games: [g2, g1], stored: [])
        XCTAssertEqual(EvaluationReadModel.effortTrend(instances).map(\.value), [3.0, 5.0])
    }

    func testSquadReadinessSortsLowestFirstAndSinksNoData() {
        let team = UUID()
        let sleepy = player(team, 1)
        let fresh = player(team, 2)
        let unrated = player(team, 3)
        let game = GameEvent(
            id: UUID(), teamID: team, opponent: "X", date: Date(),
            preMatchCheckIns: [
                sleepy.id: PreMatchCheckIn(sleep: 2, energy: 2),
                fresh.id: PreMatchCheckIn(sleep: 5, energy: 5),
            ]
        )

        let board = EvaluationReadModel.squadReadiness(
            players: [fresh, unrated, sleepy], games: [game], stored: [])

        XCTAssertEqual(board.map { $0.player.id }, [sleepy.id, fresh.id, unrated.id],
                       "lowest readiness first; the unrated player sinks to the bottom")
        XCTAssertEqual(board[0].averageReadiness!, 2.0, accuracy: 0.0001)
        XCTAssertEqual(board[0].sampleCount, 1)
        XCTAssertNil(board[2].averageReadiness)
    }

    func testEmptyDataYieldsNoTrendsOrAverage() {
        let instances = EvaluationReadModel.athleteInstances(
            playerID: UUID(), developmentLog: [], games: [], stored: [])
        XCTAssertTrue(instances.isEmpty)
        XCTAssertTrue(EvaluationReadModel.readinessTrend(instances).isEmpty)
        XCTAssertNil(EvaluationReadModel.averageReadiness(instances))
    }
}

@MainActor
final class EvaluationReadStoreTests: XCTestCase {

    func testStoreAthleteEvaluationsSpanLegacyAndEngineData() {
        let store = TestData.store()
        let player = store.players[0]

        // A game-day check-in written the legacy way (dictionary on the game).
        store.games.append(GameEvent(
            id: UUID(), teamID: store.teamID(ofPlayer: player.id)!, opponent: "Legacy FC", date: Date(),
            preMatchCheckIns: [player.id: PreMatchCheckIn(sleep: 3, energy: 3)]
        ))
        // An engine-recorded instance of a custom (non-built-in) template — these
        // unify with legacy data; built-in templates come only from the legacy
        // source, so they can't double-count.
        store.saveFormInstance(FormInstance(templateID: UUID(),
                                            context: .development, subject: .athlete(player.id),
                                            answers: [.scale("Passing", 4)]))

        let evaluations = store.athleteEvaluations(player)
        XCTAssertEqual(evaluations.filter { $0.context == .preGame }.count, 1)
        XCTAssertEqual(evaluations.filter { $0.context == .development }.count, 1)
        XCTAssertEqual(EvaluationReadModel.averageReadiness(evaluations)!, 3.0, accuracy: 0.0001)
    }
}

import XCTest
@testable import SoccerCoachKit

/// Proves the generic evaluation engine (a) faithfully represents the six
/// hand-written scored structs it's meant to replace, (b) computes the same
/// composite scores, and (c) persists and syncs like every other collection.
final class FormEngineTests: XCTestCase {

    // MARK: - The six structs collapse into seeded templates

    func testCatalogCollapsesAllSixStructs() {
        let catalog = FormTemplateCatalog.builtIns
        XCTAssertEqual(catalog.count, 6, "one template per hand-written struct")
        XCTAssertTrue(catalog.allSatisfy(\.isBuiltIn))

        // Every context the doc names for Phase 1–3 has a seeded home.
        let contexts = Set(catalog.map(\.context))
        XCTAssertTrue(contexts.isSuperset(of: [.preGame, .postGame, .development, .coachReview]))

        // Stable ids resolve back to their templates (instances depend on this).
        XCTAssertNotNil(FormTemplateCatalog.builtIn(id: FormTemplateCatalog.ID.preMatchCheckIn))
    }

    func testPreMatchTemplateMatchesStructShape() {
        let template = FormTemplateCatalog.preMatchCheckIn
        // 8 wellness scales, exactly matching PreMatchCheckIn.scales.
        XCTAssertEqual(template.scaleFields.count, 8)
        XCTAssertEqual(template.scaleFields.map(\.key), PreMatchCheckIn().scales.map { $0.key })
        // The two bools and the note are represented too.
        XCTAssertEqual(template.field(for: "warmedUp")?.kind, .bool)
        XCTAssertEqual(template.field(for: "hasPain")?.kind, .bool)
        XCTAssertEqual(template.field(for: "note")?.kind, .text)
    }

    func testDevelopmentTemplateKeysMatchSkillCategories() {
        let template = FormTemplateCatalog.developmentReview
        let scaleKeys = Set(template.scaleFields.map(\.key))
        XCTAssertEqual(scaleKeys, Set(SkillCategory.allCases.map(\.rawValue)),
                       "development ratings migrate 1:1 by SkillCategory rawValue")
    }

    // MARK: - Composite score equals the struct's own readiness

    func testScaleMeanEqualsCheckInReadiness() {
        let template = FormTemplateCatalog.preMatchCheckIn
        let cases = [
            PreMatchCheckIn(sleep: 5, energy: 4, freshness: 4, hydration: 4,
                            nutrition: 5, mood: 5, composure: 4, focus: 5),
            // Partial: unrated scales (0) must be treated as absent, not zero.
            PreMatchCheckIn(sleep: 2, energy: 0, freshness: 3, hydration: 0,
                            nutrition: 0, mood: 3, composure: 0, focus: 2, note: "partial"),
            PreMatchCheckIn(), // nothing rated
        ]

        for checkIn in cases {
            let instance = FormMigration.instance(from: checkIn, athlete: UUID(), game: UUID())
            let engineScore = FormEngine.scaleMean(of: instance, using: template)
            if let expected = checkIn.readiness {
                XCTAssertNotNil(engineScore)
                XCTAssertEqual(engineScore!, expected, accuracy: 0.0001,
                               "engine readiness must equal the struct's readiness")
            } else {
                XCTAssertNil(engineScore, "no rated scales → no score, in both models")
            }
        }
    }

    func testMeanAcrossInstancesAggregatesOneField() {
        let athlete = UUID()
        let instances = [3, 5, 4].map { sleep in
            FormMigration.instance(
                from: PreMatchCheckIn(sleep: sleep, energy: sleep),
                athlete: athlete, game: UUID()
            )
        }
        XCTAssertEqual(FormEngine.mean(ofField: "sleep", across: instances)!, 4.0, accuracy: 0.0001)
        XCTAssertNil(FormEngine.mean(ofField: "hydration", across: instances), "unrecorded field → nil")
    }

    func testSeriesIsOldestFirst() {
        let athlete = UUID()
        let now = Date()
        let older = FormInstance(templateID: FormTemplateCatalog.ID.preMatchCheckIn, context: .preGame,
                                 subject: .athlete(athlete), submittedAt: now.addingTimeInterval(-100),
                                 answers: [.scale("sleep", 2)])
        let newer = FormInstance(templateID: FormTemplateCatalog.ID.preMatchCheckIn, context: .preGame,
                                 subject: .athlete(athlete), submittedAt: now,
                                 answers: [.scale("sleep", 5)])
        let series = FormEngine.series(ofField: "sleep", across: [newer, older])
        XCTAssertEqual(series.map { $0.value }, [2, 5], "sorted oldest → newest")
    }

    // MARK: - Migration adapters produce faithful instances

    func testGameReportMigrationDropsZeroCounts() {
        let report = GamePlayerReport(minutes: 60, goals: 2, assists: 0, effort: 5, developmentFocus: "Box movement")
        let instance = FormMigration.instance(from: report, athlete: UUID(), game: UUID())
        XCTAssertEqual(instance.intValue(for: "minutes"), 60)
        XCTAssertEqual(instance.intValue(for: "goals"), 2)
        XCTAssertNil(instance.answer(for: "assists"), "a zero count is not recorded")
        XCTAssertEqual(instance.intValue(for: "effort"), 5)
        XCTAssertEqual(instance.text(for: "developmentFocus"), "Box movement")
        XCTAssertEqual(instance.context, .postGame)
    }

    func testDevelopmentEntryMigrationPreservesIdentity() {
        let entry = DevelopmentEntry(notes: "Good week", ratings: ["Passing": 4, "Tactical": 0])
        let instance = FormMigration.instance(from: entry, athlete: UUID())
        XCTAssertEqual(instance.id, entry.id, "the migrated row keeps its identity")
        XCTAssertEqual(instance.intValue(for: "Passing"), 4)
        XCTAssertNil(instance.answer(for: "Tactical"), "unrated skill is absent")
        XCTAssertEqual(instance.text(for: "notes"), "Good week")
    }

    func testCoachReviewMigratesAsTeamSubject() {
        let team = UUID()
        let review = CoachPostMatchReview(teamPerformance: 5, whatWorked: "Pressing", whatToAdjust: "Set pieces", standoutPlayer: "Ava")
        let instance = FormMigration.instance(from: review, team: team, game: UUID())
        XCTAssertEqual(instance.subject, .team(team))
        XCTAssertEqual(instance.intValue(for: "teamPerformance"), 5)
        XCTAssertEqual(instance.context, .coachReview)
    }

    // MARK: - Validation

    func testValidationFlagsOutOfRangeAndUnknownFields() {
        let template = FormTemplateCatalog.preMatchCheckIn
        let instance = FormInstance(
            templateID: template.id, context: .preGame, subject: .athlete(UUID()),
            answers: [.scale("sleep", 9), .scale("bogus", 3)]
        )
        let issues = FormEngine.validationIssues(for: instance, against: template)
        XCTAssertTrue(issues.contains { $0.contains("above maximum") }, "9 exceeds the 1...5 scale")
        XCTAssertTrue(issues.contains { $0.contains("Unknown field") }, "bogus key flagged")
    }

    func testValidCheckInHasNoIssues() {
        let template = FormTemplateCatalog.preMatchCheckIn
        let instance = FormMigration.instance(
            from: PreMatchCheckIn(sleep: 5, energy: 3, warmedUp: true, note: "ok"),
            athlete: UUID(), game: UUID()
        )
        XCTAssertEqual(FormEngine.validationIssues(for: instance, against: template), [])
    }

    // MARK: - Backward-compatible persistence

    func testSnapshotWithoutFormKeysDecodesToEmpty() throws {
        // A blob saved before the engine existed has no form keys at all.
        let legacy = """
        {"schemaVersion":1,"dataVersion":3,"teams":[],"players":[],"drills":[],
         "sessions":[],"diagrams":[],"games":[],"events":[],
         "selectedTeamID":"\(UUID().uuidString)"}
        """.data(using: .utf8)!
        let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: legacy)
        XCTAssertEqual(snapshot.formTemplates, [])
        XCTAssertEqual(snapshot.formInstances, [])
    }

    func testSnapshotFormRoundTrips() throws {
        let instance = FormInstance(templateID: FormTemplateCatalog.ID.preMatchCheckIn, context: .preGame,
                                    subject: .athlete(UUID()), contextRef: .game(UUID()),
                                    answers: [.scale("sleep", 4), .bool("hasPain", false), .text("note", "hi")])
        let snapshot = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                   games: [], events: [], selectedTeamID: UUID(), formInstances: [instance])
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: data)
        XCTAssertEqual(decoded.formInstances, [instance], "instance survives a Codable round trip intact")
    }

    // MARK: - CloudKit per-record sync

    func testFormInstancesSyncAsRecords() {
        let instance = FormInstance(templateID: FormTemplateCatalog.ID.developmentReview, context: .development,
                                    subject: .athlete(UUID()), answers: [.scale("Passing", 4)])
        let source = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                 games: [], events: [], selectedTeamID: UUID(), formInstances: [instance])
        let records = SyncRecords.records(from: source)
        XCTAssertTrue(records.contains { $0.type == .formInstance && $0.id == instance.id.uuidString })

        // Applying those records into a fresh snapshot reconstitutes the instance.
        var target = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                 games: [], events: [], selectedTeamID: source.selectedTeamID)
        for record in records { SyncRecords.apply(record, to: &target) }
        XCTAssertEqual(target.formInstances, [instance])
    }
}

@MainActor
final class FormStoreTests: XCTestCase {

    func testSaveDropsEmptyAndPersistsRealInstances() {
        let store = TestData.store()
        let athlete = store.players[0].id

        let empty = FormInstance(templateID: FormTemplateCatalog.ID.preMatchCheckIn,
                                 context: .preGame, subject: .athlete(athlete))
        store.saveFormInstance(empty)
        XCTAssertTrue(store.formInstances.isEmpty, "an untouched form is not stored")

        let real = FormInstance(templateID: FormTemplateCatalog.ID.preMatchCheckIn,
                                context: .preGame, subject: .athlete(athlete),
                                answers: [.scale("sleep", 4)])
        store.saveFormInstance(real)
        XCTAssertEqual(store.formInstances.count, 1)

        // Saving the same id again replaces rather than appends.
        var edited = real
        edited.answers = [.scale("sleep", 5)]
        store.saveFormInstance(edited)
        XCTAssertEqual(store.formInstances.count, 1)
        XCTAssertEqual(store.formInstances.first?.intValue(for: "sleep"), 5)
    }

    func testAllFormTemplatesMergesBuiltInsAndCustom() {
        let store = TestData.store()
        XCTAssertEqual(store.allFormTemplates.count, FormTemplateCatalog.builtIns.count)

        let custom = FormTemplate(id: UUID(), context: .tryout, subjectType: .athlete,
                                  name: "Spring Tryout", fields: [
                                    FormField(key: "speed", label: "Speed", kind: .scale, position: 0, config: .scale())
                                  ])
        store.saveFormTemplate(custom)
        XCTAssertEqual(store.allFormTemplates.count, FormTemplateCatalog.builtIns.count + 1)
        XCTAssertNotNil(store.formTemplate(id: custom.id))

        // Built-ins can't be shadowed by a save.
        var fakeBuiltIn = FormTemplateCatalog.preMatchCheckIn
        fakeBuiltIn.name = "Hijacked"
        store.saveFormTemplate(fakeBuiltIn)
        XCTAssertEqual(store.formTemplate(id: FormTemplateCatalog.ID.preMatchCheckIn)?.name,
                       "Pre-Match Check-In", "built-in template is protected")
    }

    func testDeletingPlayerRemovesTheirInstances() {
        let store = TestData.store()
        let keep = store.players[0].id
        let remove = store.players[1]
        store.saveFormInstance(FormInstance(templateID: FormTemplateCatalog.ID.developmentReview,
                                            context: .development, subject: .athlete(keep),
                                            answers: [.scale("Passing", 4)]))
        store.saveFormInstance(FormInstance(templateID: FormTemplateCatalog.ID.developmentReview,
                                            context: .development, subject: .athlete(remove.id),
                                            answers: [.scale("Passing", 3)]))

        store.deletePlayer(remove)

        XCTAssertEqual(store.formInstances.count, 1, "the removed player's responses go with them")
        XCTAssertEqual(store.formInstances.first?.subject.id, keep)
    }

    func testInstancesForSubjectAreNewestFirst() {
        let store = TestData.store()
        let athlete = store.players[0].id
        let now = Date()
        store.saveFormInstance(FormInstance(templateID: FormTemplateCatalog.ID.preMatchCheckIn,
                                            context: .preGame, subject: .athlete(athlete),
                                            submittedAt: now.addingTimeInterval(-100),
                                            answers: [.scale("sleep", 2)]))
        store.saveFormInstance(FormInstance(templateID: FormTemplateCatalog.ID.preMatchCheckIn,
                                            context: .preGame, subject: .athlete(athlete),
                                            submittedAt: now, answers: [.scale("sleep", 5)]))

        let history = store.formInstances(for: .athlete(athlete), context: .preGame)
        XCTAssertEqual(history.map { $0.intValue(for: "sleep") }, [5, 2], "newest first")
    }
}

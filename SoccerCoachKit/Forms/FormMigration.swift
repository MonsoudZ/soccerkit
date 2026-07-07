import Foundation

/// Converters from today's hand-written evaluation structs into generic
/// `FormInstance`s over the seeded catalog templates.
///
/// These are deliberately **inert**: nothing in the live app calls them yet, so
/// this ships the engine without rewriting a single existing flow. They exist to
/// prove the path (and are exercised by tests): when you flip a flow over to the
/// engine, you migrate its stored dictionaries with the matching function here,
/// then delete the struct. That is the "going-forward discipline, not a big-bang
/// rewrite" the plan calls for.
///
/// Convention: a scale recorded as `0` means "not asked" in the old structs, so
/// it becomes an *absent* answer (nil), not a `0` — which is what keeps the
/// engine's `scaleMean` identical to the struct's own `readiness`.
enum FormMigration {

    // MARK: - Pre-match check-in

    static func instance(from checkIn: PreMatchCheckIn, athlete: UUID, game: UUID,
                         submittedAt: Date = Date()) -> FormInstance {
        var answers: [FormAnswer] = checkIn.scales
            .filter { $0.value > 0 }
            .map { .scale($0.key, $0.value) }
        if let warmedUp = checkIn.warmedUp { answers.append(.bool("warmedUp", warmedUp)) }
        if let hasPain = checkIn.hasPain { answers.append(.bool("hasPain", hasPain)) }
        let note = checkIn.note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !note.isEmpty { answers.append(.text("note", checkIn.note)) }
        return FormInstance(
            templateID: FormTemplateCatalog.ID.preMatchCheckIn,
            templateVersion: FormTemplateCatalog.preMatchCheckIn.version,
            context: .preGame,
            subject: .athlete(athlete),
            contextRef: .game(game),
            submittedAt: submittedAt,
            answers: answers
        )
    }

    // MARK: - Post-match reflection

    static func instance(from reflection: PostMatchReflection, athlete: UUID, game: UUID,
                         submittedAt: Date = Date()) -> FormInstance {
        var answers: [FormAnswer] = reflection.scales
            .filter { $0.value > 0 }
            .map { .scale($0.key, $0.value) }
        if let hadInjury = reflection.hadInjury { answers.append(.bool("hadInjury", hadInjury)) }
        if !reflection.wentWell.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            answers.append(.text("wentWell", reflection.wentWell))
        }
        if !reflection.workOn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            answers.append(.text("workOn", reflection.workOn))
        }
        return FormInstance(
            templateID: FormTemplateCatalog.ID.postMatchReflection,
            templateVersion: FormTemplateCatalog.postMatchReflection.version,
            context: .postGame,
            subject: .athlete(athlete),
            contextRef: .game(game),
            submittedAt: submittedAt,
            answers: answers
        )
    }

    // MARK: - Player game report

    static func instance(from report: GamePlayerReport, athlete: UUID, game: UUID,
                         submittedAt: Date = Date()) -> FormInstance {
        var answers: [FormAnswer] = []
        if report.minutes != 0 { answers.append(.number("minutes", report.minutes)) }
        if report.goals != 0 { answers.append(.number("goals", report.goals)) }
        if report.assists != 0 { answers.append(.number("assists", report.assists)) }
        if report.effort > 0 { answers.append(.scale("effort", report.effort)) }
        if !report.developmentFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            answers.append(.text("developmentFocus", report.developmentFocus))
        }
        return FormInstance(
            templateID: FormTemplateCatalog.ID.playerGameReport,
            templateVersion: FormTemplateCatalog.playerGameReport.version,
            context: .postGame,
            subject: .athlete(athlete),
            contextRef: .game(game),
            submittedAt: submittedAt,
            answers: answers
        )
    }

    // MARK: - Development entry

    static func instance(from entry: DevelopmentEntry, athlete: UUID) -> FormInstance {
        var answers: [FormAnswer] = entry.ratings
            .filter { $0.value > 0 }
            .map { .scale($0.key, $0.value) }
        if !entry.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            answers.append(.text("notes", entry.notes))
        }
        return FormInstance(
            id: entry.id, // preserve identity so a migrated log keeps its row id
            templateID: FormTemplateCatalog.ID.developmentReview,
            templateVersion: FormTemplateCatalog.developmentReview.version,
            context: .development,
            subject: .athlete(athlete),
            submittedAt: entry.date,
            answers: answers
        )
    }

    // MARK: - Coach reviews (team subject)

    static func instance(from plan: CoachPreMatchPlan, team: UUID, game: UUID,
                         submittedAt: Date = Date()) -> FormInstance {
        var answers: [FormAnswer] = []
        if !plan.objective.isEmpty { answers.append(.text("objective", plan.objective)) }
        if !plan.keyMatchup.isEmpty { answers.append(.text("keyMatchup", plan.keyMatchup)) }
        if !plan.focusPoints.isEmpty { answers.append(.text("focusPoints", plan.focusPoints)) }
        if !plan.watchFor.isEmpty { answers.append(.text("watchFor", plan.watchFor)) }
        return FormInstance(
            templateID: FormTemplateCatalog.ID.coachPreMatchPlan,
            templateVersion: FormTemplateCatalog.coachPreMatchPlan.version,
            context: .coachReview,
            subject: .team(team),
            contextRef: .game(game),
            submittedAt: submittedAt,
            answers: answers
        )
    }

    static func instance(from review: CoachPostMatchReview, team: UUID, game: UUID,
                         submittedAt: Date = Date()) -> FormInstance {
        var answers: [FormAnswer] = []
        if review.teamPerformance > 0 { answers.append(.scale("teamPerformance", review.teamPerformance)) }
        if !review.whatWorked.isEmpty { answers.append(.text("whatWorked", review.whatWorked)) }
        if !review.whatToAdjust.isEmpty { answers.append(.text("whatToAdjust", review.whatToAdjust)) }
        if !review.standoutPlayer.isEmpty { answers.append(.text("standoutPlayer", review.standoutPlayer)) }
        return FormInstance(
            templateID: FormTemplateCatalog.ID.coachPostMatchReview,
            templateVersion: FormTemplateCatalog.coachPostMatchReview.version,
            context: .coachReview,
            subject: .team(team),
            contextRef: .game(game),
            submittedAt: submittedAt,
            answers: answers
        )
    }
}

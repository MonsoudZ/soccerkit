import Foundation

/// The seeded, built-in evaluation templates that ship in the app.
///
/// This is the load-bearing proof of the architecture: the six fixed-schema
/// structs the app grew by hand — `PreMatchCheckIn`, `PostMatchReflection`,
/// `GamePlayerReport`, `DevelopmentEntry`, `CoachPreMatchPlan`,
/// `CoachPostMatchReview` — are all the *same primitive*: a dated, scored,
/// noted response about a subject in a context. Here each one collapses into a
/// `FormTemplate`, i.e. seed data rather than code. New evaluation flows add a
/// template here (or a user/org-owned one); they do **not** add another struct.
///
/// Built-ins live in code (not persisted) with stable ids, so they always match
/// the current app version and existing `FormInstance`s keep resolving their
/// template across launches and devices.
enum FormTemplateCatalog {

    // Stable ids so instances reference the right template forever.
    enum ID {
        static let preMatchCheckIn   = UUID(uuidString: "F0000000-0000-0000-0000-000000000001")!
        static let postMatchReflection = UUID(uuidString: "F0000000-0000-0000-0000-000000000002")!
        static let playerGameReport  = UUID(uuidString: "F0000000-0000-0000-0000-000000000003")!
        static let developmentReview = UUID(uuidString: "F0000000-0000-0000-0000-000000000004")!
        static let coachPreMatchPlan = UUID(uuidString: "F0000000-0000-0000-0000-000000000005")!
        static let coachPostMatchReview = UUID(uuidString: "F0000000-0000-0000-0000-000000000006")!
    }

    /// Every template that ships with the app, in a sensible display order.
    static let builtIns: [FormTemplate] = [
        preMatchCheckIn,
        postMatchReflection,
        playerGameReport,
        developmentReview,
        coachPreMatchPlan,
        coachPostMatchReview,
    ]

    static func builtIn(id: UUID) -> FormTemplate? { builtIns.first { $0.id == id } }

    // MARK: - Pre-match check-in  (was `PreMatchCheckIn`)

    /// 8 wellness scales (higher = better, so their mean is a readiness score) +
    /// two yes/no fields + a note — exactly the fields of `PreMatchCheckIn`.
    static let preMatchCheckIn = FormTemplate(
        id: ID.preMatchCheckIn,
        context: .preGame,
        subjectType: .athlete,
        name: "Pre-Match Check-In",
        fields: scaleFields([
            ("sleep", "Sleep"),
            ("energy", "Energy"),
            ("freshness", "Freshness"),
            ("hydration", "Hydration"),
            ("nutrition", "Nutrition"),
            ("mood", "Mood"),
            ("composure", "Composure"),
            ("focus", "Focus"),
        ]) + [
            FormField(key: "warmedUp", label: "Warmed up", kind: .bool, position: 8),
            FormField(key: "hasPain", label: "Has pain", kind: .bool, position: 9),
            FormField(key: "note", label: "Note", kind: .text, position: 10),
        ],
        isBuiltIn: true
    )

    // MARK: - Post-match reflection  (was `PostMatchReflection`)

    static let postMatchReflection = FormTemplate(
        id: ID.postMatchReflection,
        context: .postGame,
        subjectType: .athlete,
        name: "Post-Match Reflection",
        fields: scaleFields([
            ("exertion", "Effort (RPE)"),
            ("performance", "Performance"),
            ("enjoyment", "Enjoyment"),
            ("fatigue", "Fatigue"),
            ("confidence", "Confidence"),
        ]) + [
            FormField(key: "hadInjury", label: "Had injury", kind: .bool, position: 5),
            FormField(key: "wentWell", label: "What went well", kind: .text, position: 6),
            FormField(key: "workOn", label: "What to work on", kind: .text, position: 7),
        ],
        isBuiltIn: true
    )

    // MARK: - Player game report  (was `GamePlayerReport`)

    /// The coach's post-game record for one player. `minutes/goals/assists` are
    /// counts (`number`), `effort` a 1–5 scale, plus a development focus note.
    static let playerGameReport = FormTemplate(
        id: ID.playerGameReport,
        context: .postGame,
        subjectType: .athlete,
        name: "Player Game Report",
        fields: [
            FormField(key: "minutes", label: "Minutes", kind: .number, position: 0, config: .number()),
            FormField(key: "goals", label: "Goals", kind: .number, position: 1, config: .number()),
            FormField(key: "assists", label: "Assists", kind: .number, position: 2, config: .number()),
            FormField(key: "effort", label: "Effort", kind: .scale, position: 3, config: .scale()),
            FormField(key: "developmentFocus", label: "Development focus", kind: .text, position: 4),
        ],
        isBuiltIn: true
    )

    // MARK: - Development review  (was `DevelopmentEntry`)

    /// The six `SkillCategory` ratings plus notes. The rating keys match
    /// `SkillCategory.rawValue`, so existing development logs migrate 1:1.
    static let developmentReview = FormTemplate(
        id: ID.developmentReview,
        context: .development,
        subjectType: .athlete,
        name: "Development Review",
        fields: scaleFields([
            ("Technical", "Technical"),
            ("Passing", "Passing"),
            ("Shooting", "Shooting"),
            ("Defending", "Defending"),
            ("Tactical", "Tactical"),
            ("Attitude", "Attitude"),
        ]) + [
            FormField(key: "notes", label: "Notes", kind: .text, position: 6),
        ],
        isBuiltIn: true
    )

    // MARK: - Coach pre-match plan  (was `CoachPreMatchPlan`)

    static let coachPreMatchPlan = FormTemplate(
        id: ID.coachPreMatchPlan,
        context: .coachReview,
        subjectType: .team,
        name: "Coach Pre-Match Plan",
        fields: [
            FormField(key: "objective", label: "Objective", kind: .text, position: 0),
            FormField(key: "keyMatchup", label: "Key matchup", kind: .text, position: 1),
            FormField(key: "focusPoints", label: "Focus points", kind: .text, position: 2),
            FormField(key: "watchFor", label: "Watch for", kind: .text, position: 3),
        ],
        isBuiltIn: true
    )

    // MARK: - Coach post-match review  (was `CoachPostMatchReview`)

    static let coachPostMatchReview = FormTemplate(
        id: ID.coachPostMatchReview,
        context: .coachReview,
        subjectType: .team,
        name: "Coach Post-Match Review",
        fields: [
            FormField(key: "teamPerformance", label: "Team performance", kind: .scale, position: 0, config: .scale()),
            FormField(key: "whatWorked", label: "What worked", kind: .text, position: 1),
            FormField(key: "whatToAdjust", label: "What to adjust", kind: .text, position: 2),
            FormField(key: "standoutPlayer", label: "Standout player", kind: .text, position: 3),
        ],
        isBuiltIn: true
    )

    // MARK: - Helpers

    /// Builds a run of 1–5 "higher is better" scale fields, numbered from 0.
    private static func scaleFields(_ items: [(key: String, label: String)]) -> [FormField] {
        items.enumerated().map { index, item in
            FormField(key: item.key, label: item.label, kind: .scale, position: index, config: .scale())
        }
    }
}

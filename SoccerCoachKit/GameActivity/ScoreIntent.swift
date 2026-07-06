import AppIntents

/// Which side scored, for the interactive Live Activity goal buttons.
enum GoalSide: String, AppEnum {
    case home
    case away

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Side")
    static var caseDisplayRepresentations: [GoalSide: DisplayRepresentation] = [
        .home: "Home",
        .away: "Away",
    ]
}

/// Records a goal directly from the Game Day Live Activity, without opening the
/// app. As a `LiveActivityIntent` it runs in the app's process, so it reaches
/// the same `GameActivityController` the app uses.
@available(iOS 17.0, *)
struct RecordGoalIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Record a goal"
    static var description = IntentDescription("Add a goal to the live match score.")

    @Parameter(title: "Side")
    var side: GoalSide

    init() {}
    init(side: GoalSide) { self.side = side }

    func perform() async throws -> some IntentResult {
        await GameActivityController.shared.adjustScore(
            homeDelta: side == .home ? 1 : 0,
            awayDelta: side == .away ? 1 : 0
        )
        return .result()
    }
}

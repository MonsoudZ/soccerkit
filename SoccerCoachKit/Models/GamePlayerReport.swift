import Foundation

/// A coach's post-game record for a single player: scoring contributions, an
/// effort rating, and a development focus for next time.
struct GamePlayerReport: Hashable, Codable {
    var goals: Int
    var assists: Int
    /// 0 = unrated, otherwise 1...5.
    var effort: Int
    var developmentFocus: String

    init(goals: Int = 0, assists: Int = 0, effort: Int = 0, developmentFocus: String = "") {
        self.goals = goals
        self.assists = assists
        self.effort = effort
        self.developmentFocus = developmentFocus
    }

    /// True when nothing has been recorded, so blank reports can be dropped
    /// instead of persisted.
    var isEmpty: Bool {
        goals == 0
            && assists == 0
            && effort == 0
            && developmentFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

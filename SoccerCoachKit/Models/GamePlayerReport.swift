import Foundation

/// A coach's post-game record for a single player: minutes played, scoring
/// contributions, an effort rating, and a development focus for next time.
struct GamePlayerReport: Hashable, Codable {
    /// Minutes the player was on the pitch; 0 when not recorded.
    var minutes: Int
    var goals: Int
    var assists: Int
    /// 0 = unrated, otherwise 1...5.
    var effort: Int
    var developmentFocus: String

    init(minutes: Int = 0, goals: Int = 0, assists: Int = 0, effort: Int = 0, developmentFocus: String = "") {
        self.minutes = minutes
        self.goals = goals
        self.assists = assists
        self.effort = effort
        self.developmentFocus = developmentFocus
    }

    enum CodingKeys: String, CodingKey {
        case minutes, goals, assists, effort, developmentFocus
    }

    // Custom decode so reports saved before `minutes` existed still load.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minutes = try container.decodeIfPresent(Int.self, forKey: .minutes) ?? 0
        goals = try container.decodeIfPresent(Int.self, forKey: .goals) ?? 0
        assists = try container.decodeIfPresent(Int.self, forKey: .assists) ?? 0
        effort = try container.decodeIfPresent(Int.self, forKey: .effort) ?? 0
        developmentFocus = try container.decodeIfPresent(String.self, forKey: .developmentFocus) ?? ""
    }

    /// True when nothing has been recorded, so blank reports can be dropped
    /// instead of persisted.
    var isEmpty: Bool {
        minutes == 0
            && goals == 0
            && assists == 0
            && effort == 0
            && developmentFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

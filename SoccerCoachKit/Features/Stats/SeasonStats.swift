import Foundation

/// A team's record aggregated from games that have a recorded final score.
struct TeamRecord: Equatable {
    var wins = 0
    var losses = 0
    var draws = 0
    var goalsFor = 0
    var goalsAgainst = 0

    var played: Int { wins + losses + draws }
    var goalDifference: Int { goalsFor - goalsAgainst }
    var summary: String { "\(wins)-\(losses)-\(draws)" }
}

/// A player's season totals aggregated from post-game reports and attendance.
struct PlayerSeasonStats: Identifiable {
    let player: Player
    var goals: Int
    var assists: Int
    var gamesPlayed: Int
    /// Mean effort rating across games where effort was recorded; 0 when none.
    var averageEffort: Double

    var id: UUID { player.id }
    /// Goal contributions (goals + assists), used for ranking.
    var contributions: Int { goals + assists }

    /// A spoken summary for VoiceOver on the season stats rows.
    var accessibilityLabel: String {
        var parts = ["\(player.name), number \(player.number)"]
        if goals > 0 { parts.append("\(goals) goal\(goals == 1 ? "" : "s")") }
        if assists > 0 { parts.append("\(assists) assist\(assists == 1 ? "" : "s")") }
        parts.append("\(gamesPlayed) game\(gamesPlayed == 1 ? "" : "s") played")
        if averageEffort > 0 { parts.append(String(format: "average effort %.1f of 5", averageEffort)) }
        return parts.joined(separator: ", ")
    }
}

/// Pure aggregation over the team's games — kept free of the store/UI so it can
/// be unit-tested directly.
enum SeasonStats {

    static func teamRecord(games: [GameEvent]) -> TeamRecord {
        var record = TeamRecord()
        for game in games {
            guard let team = game.teamScore, let opponent = game.opponentScore else { continue }
            record.goalsFor += team
            record.goalsAgainst += opponent
            if team > opponent { record.wins += 1 }
            else if team < opponent { record.losses += 1 }
            else { record.draws += 1 }
        }
        return record
    }

    /// Per-player totals, ranked by goal contributions then jersey number.
    static func playerStats(players: [Player], games: [GameEvent]) -> [PlayerSeasonStats] {
        players.map { player in
            var goals = 0
            var assists = 0
            var gamesPlayed = 0
            var effortSamples: [Int] = []

            for game in games {
                if let report = game.playerReports[player.id] {
                    goals += report.goals
                    assists += report.assists
                    if report.effort > 0 { effortSamples.append(report.effort) }
                }
                if let status = game.attendance[player.id], status == .present || status == .late {
                    gamesPlayed += 1
                }
            }

            let averageEffort = effortSamples.isEmpty
                ? 0
                : Double(effortSamples.reduce(0, +)) / Double(effortSamples.count)

            return PlayerSeasonStats(player: player, goals: goals, assists: assists,
                                     gamesPlayed: gamesPlayed, averageEffort: averageEffort)
        }
        .sorted { lhs, rhs in
            lhs.contributions != rhs.contributions
                ? lhs.contributions > rhs.contributions
                : lhs.player.number < rhs.player.number
        }
    }
}

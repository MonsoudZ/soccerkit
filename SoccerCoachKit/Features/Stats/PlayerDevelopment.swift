import Foundation

/// The team's outcome in a single game, from the player's perspective.
enum GameOutcome: String {
    case win = "W"
    case loss = "L"
    case draw = "D"
}

/// One game in a player's season timeline: whether they attended, what they
/// contributed, and how the team did. Oldest-first when produced.
struct PlayerGameLine: Identifiable {
    let gameID: UUID
    let date: Date
    let opponent: String
    /// Present or late (i.e. actually took part), from recorded attendance.
    let attended: Bool
    /// Minutes played, from the post-game report; 0 when not recorded.
    let minutes: Int
    let goals: Int
    let assists: Int
    /// 0 = unrated, otherwise 1...5.
    let effort: Int
    /// The team result once a final score exists; `nil` while unplayed.
    let outcome: GameOutcome?

    var id: UUID { gameID }
    var contributions: Int { goals + assists }
}

/// A player's development profile aggregated across the team's games — season
/// totals plus a per-game timeline for trend/form display. Pure and store-free
/// so it can be unit-tested directly, mirroring `SeasonStats`.
struct PlayerDevelopment {
    /// Total minutes played across games with a recorded report.
    let minutes: Int
    let goals: Int
    let assists: Int
    /// Mean effort across games where effort was recorded; 0 when none.
    let averageEffort: Double
    /// Games marked present or late.
    let gamesAttended: Int
    /// Games where an attendance status was recorded for this player (the
    /// attendance-rate denominator).
    let gamesTracked: Int
    /// Every game that has attendance or a report for this player, oldest-first.
    let timeline: [PlayerGameLine]

    var contributions: Int { goals + assists }

    /// Fraction present/late out of tracked games; `nil` when nothing tracked.
    var attendanceRate: Double? {
        gamesTracked == 0 ? nil : Double(gamesAttended) / Double(gamesTracked)
    }

    /// The most recent `count` games that the player actually took part in,
    /// most-recent-last (so a sparkline reads left→right in time).
    func recentForm(_ count: Int = 6) -> [PlayerGameLine] {
        Array(timeline.filter(\.attended).suffix(count))
    }

    static func profile(for player: Player, games: [GameEvent]) -> PlayerDevelopment {
        var minutes = 0
        var goals = 0
        var assists = 0
        var effortSamples: [Int] = []
        var gamesAttended = 0
        var gamesTracked = 0
        var timeline: [PlayerGameLine] = []

        for game in games.sorted(by: { $0.date < $1.date }) {
            let report = game.playerReports[player.id]
            let status = game.attendance[player.id]
            // Skip games with nothing recorded for this player at all.
            guard report != nil || status != nil else { continue }

            let attended = status == .present || status == .late
            if status != nil {
                gamesTracked += 1
                if attended { gamesAttended += 1 }
            }

            let m = report?.minutes ?? 0
            let g = report?.goals ?? 0
            let a = report?.assists ?? 0
            minutes += m
            goals += g
            assists += a
            if let effort = report?.effort, effort > 0 { effortSamples.append(effort) }

            timeline.append(
                PlayerGameLine(
                    gameID: game.id,
                    date: game.date,
                    opponent: game.opponent,
                    attended: attended,
                    minutes: m,
                    goals: g,
                    assists: a,
                    effort: report?.effort ?? 0,
                    outcome: outcome(of: game)
                )
            )
        }

        let averageEffort = effortSamples.average ?? 0

        return PlayerDevelopment(
            minutes: minutes,
            goals: goals,
            assists: assists,
            averageEffort: averageEffort,
            gamesAttended: gamesAttended,
            gamesTracked: gamesTracked,
            timeline: timeline
        )
    }

    private static func outcome(of game: GameEvent) -> GameOutcome? {
        guard let team = game.teamScore, let opponent = game.opponentScore else { return nil }
        if team > opponent { return .win }
        if team < opponent { return .loss }
        return .draw
    }
}

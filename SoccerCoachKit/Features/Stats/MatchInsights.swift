import Foundation

/// One pre-match factor compared between a player's strong and weak games.
struct FactorComparison: Identifiable {
    let key: String
    let label: String
    let strongAverage: Double
    let weakAverage: Double

    /// How much higher this factor runs on strong games than weak ones. A large
    /// positive gap is the actionable signal ("sleep is much better before good
    /// games").
    var gap: Double { strongAverage - weakAverage }
    var id: String { key }
}

/// What a player's match questionnaires reveal — average readiness plus the
/// factors that most separate their good games from their poor ones.
struct PlayerMatchInsight {
    let averageReadiness: Double?
    let gamesWithCheckIn: Int
    let strongGameCount: Int
    let weakGameCount: Int
    /// Factors present in both strong and weak games, biggest differentiator first.
    let differentiators: [FactorComparison]

    /// Enough strong and weak games (with check-ins) to compare.
    var hasComparison: Bool { strongGameCount > 0 && weakGameCount > 0 && !differentiators.isEmpty }
    var topDifferentiator: FactorComparison? { differentiators.first }
}

/// Pure aggregation over a player's match questionnaires. No store/UI, so it's
/// directly unit-testable — mirrors `SeasonStats` / `PlayerDevelopment`.
enum MatchInsights {

    /// The rating used to judge how well a player played in a game: their
    /// post-match performance self-rating, falling back to the coach's effort
    /// rating in the post-game report. `nil` when neither is recorded.
    static func performanceRating(for playerID: UUID, in game: GameEvent) -> Int? {
        if let performance = game.postMatchReflections[playerID]?.performance, performance > 0 {
            return performance
        }
        if let effort = game.playerReports[playerID]?.effort, effort > 0 {
            return effort
        }
        return nil
    }

    static func insight(for playerID: UUID, games: [GameEvent]) -> PlayerMatchInsight {
        var readinessSamples: [Double] = []
        var strong: [String: [Int]] = [:]
        var weak: [String: [Int]] = [:]
        var strongGames = 0
        var weakGames = 0
        var checkInCount = 0

        for game in games {
            guard let checkIn = game.preMatchCheckIns[playerID], !checkIn.isEmpty else { continue }
            checkInCount += 1
            if let readiness = checkIn.readiness { readinessSamples.append(readiness) }

            guard let rating = performanceRating(for: playerID, in: game) else { continue }
            if rating >= 4 {
                strongGames += 1
                accumulate(checkIn, into: &strong)
            } else if rating <= 2 {
                weakGames += 1
                accumulate(checkIn, into: &weak)
            }
        }

        let averageReadiness = readinessSamples.isEmpty
            ? nil
            : readinessSamples.reduce(0, +) / Double(readinessSamples.count)

        let labels = Dictionary(uniqueKeysWithValues: PreMatchCheckIn().scales.map { ($0.key, $0.label) })
        var comparisons: [FactorComparison] = []
        for (key, strongValues) in strong {
            guard let strongAvg = strongValues.average, let weakAvg = weak[key]?.average else { continue }
            comparisons.append(
                FactorComparison(
                    key: key,
                    label: labels[key] ?? key,
                    strongAverage: strongAvg,
                    weakAverage: weakAvg
                )
            )
        }
        // Biggest positive gap first; break ties by label for stable ordering.
        comparisons.sort { $0.gap != $1.gap ? $0.gap > $1.gap : $0.label < $1.label }

        return PlayerMatchInsight(
            averageReadiness: averageReadiness,
            gamesWithCheckIn: checkInCount,
            strongGameCount: strongGames,
            weakGameCount: weakGames,
            differentiators: comparisons
        )
    }

    private static func accumulate(_ checkIn: PreMatchCheckIn, into bucket: inout [String: [Int]]) {
        for scale in checkIn.scales where scale.value > 0 {
            bucket[scale.key, default: []].append(scale.value)
        }
    }
}

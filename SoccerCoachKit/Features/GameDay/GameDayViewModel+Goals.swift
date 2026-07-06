import Foundation

extension GameDayViewModel {
    // MARK: - Playing-time goals

    private var totalGameSeconds: Int { max(defaultGameMinutes * 60, 1) }

    /// The minimum-minutes goal for a player, in seconds. A per-player override
    /// wins over the team default; zero means no goal.
    func minimumSeconds(for player: Player) -> Int {
        max(0, (player.minMinutesOverride ?? defaultMinimumMinutes)) * 60
    }

    /// Progress toward the player's minimum-minutes goal, 0...1 (1 when no goal).
    func goalProgress(for player: Player) -> Double {
        let goal = minimumSeconds(for: player)
        guard goal > 0 else { return 1 }
        return min(1, Double(playingSeconds[player.id, default: 0]) / Double(goal))
    }

    func hasReachedGoal(_ player: Player) -> Bool {
        playingSeconds[player.id, default: 0] >= minimumSeconds(for: player)
    }

    /// A player is at risk when the minutes they still owe can only be met by
    /// keeping them on the field for essentially all of the remaining game.
    func isAtRiskOfMissingGoal(_ player: Player) -> Bool {
        guard status(for: player) == .available else { return false }
        let deficit = minimumSeconds(for: player) - playingSeconds[player.id, default: 0]
        guard deficit > 0 else { return false }
        let remaining = max(0, totalGameSeconds - elapsedSeconds)
        // Strictly greater: a player who could reach the goal by playing exactly
        // all remaining time is not yet at risk.
        return deficit > remaining
    }
}

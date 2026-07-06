import Foundation

extension GameDayViewModel {
    // MARK: - Balanced-sub suggestion

    /// How far a player is above (positive) or below (negative) their goal.
    private func balanceScore(_ player: Player) -> Int {
        playingSeconds[player.id, default: 0] - minimumSeconds(for: player)
    }

    /// Suggests swapping the most over-served available starter for the most
    /// under-served available bench player, to even out minutes toward goals.
    var suggestedSub: (out: Player, inPlayer: Player)? {
        guard
            let out = availableStarterPlayers.max(by: { balanceScore($0) < balanceScore($1) }),
            let inPlayer = availableBenchPlayers.min(by: { balanceScore($0) < balanceScore($1) })
        else { return nil }

        // Only suggest when the swap actually reduces the imbalance.
        guard balanceScore(inPlayer) < balanceScore(out) else { return nil }
        return (out, inPlayer)
    }

    var suggestedSubText: String {
        guard let suggestion = suggestedSub else { return "Minutes look balanced." }
        return "\(suggestion.inPlayer.name) in for \(suggestion.out.name)"
    }

    /// Loads the balanced-sub suggestion into the Quick Sub selections so the
    /// coach can review it before recording.
    func selectSuggestedSub() {
        guard let suggestion = suggestedSub else { return }
        selectedOutPlayerID = suggestion.out.id
        selectedInPlayerID = suggestion.inPlayer.id
    }
}

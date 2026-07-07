import Foundation

/// How available a player is for a specific game, worst-first for triage.
enum AvailabilityLevel: Int, Comparable {
    case flagged     // planning to play but a concern (injury/pain or low readiness)
    case out         // RSVP'd not going
    case noResponse  // hasn't RSVP'd
    case maybe       // RSVP'd maybe (no concerns)
    case available   // RSVP'd going (no concerns)

    static func < (lhs: AvailabilityLevel, rhs: AvailabilityLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .flagged: return "Needs a look"
        case .out: return "Out"
        case .noResponse: return "No response"
        case .maybe: return "Maybe"
        case .available: return "Available"
        }
    }
}

/// One player's availability read for a game: their RSVP, computed level, and any
/// concern flags.
struct PlayerAvailability: Identifiable {
    let player: Player
    let rsvp: RSVPStatus
    let level: AvailabilityLevel
    let flags: [String]

    var id: UUID { player.id }
}

/// A one-line tally of the squad for the game header.
struct AvailabilitySummary {
    var available = 0
    var maybe = 0
    var flagged = 0
    var out = 0
    var noResponse = 0
}

/// Pure aggregation that pulls RSVP + the latest readiness/injury signals into a
/// pre-game availability board. No store/UI, so it's directly unit-testable.
enum SquadAvailability {
    /// Readiness at or below this (1–5) is treated as a concern.
    static let lowReadinessThreshold = 2.5

    static func board(players: [Player], game: GameEvent, history: [GameEvent]) -> [PlayerAvailability] {
        let priorGames = history
            .filter { $0.id != game.id && $0.date < game.date }
            .sorted { $0.date > $1.date }

        return players
            .map { player in
                let rsvp = game.rsvps[player.id] ?? .noResponse
                let flags = concerns(for: player.id, game: game, priorGames: priorGames)
                return PlayerAvailability(
                    player: player,
                    rsvp: rsvp,
                    level: level(rsvp: rsvp, hasConcerns: !flags.isEmpty),
                    flags: flags
                )
            }
            .sorted { lhs, rhs in
                lhs.level != rhs.level ? lhs.level < rhs.level : lhs.player.number < rhs.player.number
            }
    }

    static func summary(_ board: [PlayerAvailability]) -> AvailabilitySummary {
        var summary = AvailabilitySummary()
        for entry in board {
            switch entry.level {
            case .available: summary.available += 1
            case .maybe: summary.maybe += 1
            case .flagged: summary.flagged += 1
            case .out: summary.out += 1
            case .noResponse: summary.noResponse += 1
            }
        }
        return summary
    }

    // MARK: - Internals

    private static func level(rsvp: RSVPStatus, hasConcerns: Bool) -> AvailabilityLevel {
        if rsvp == .notGoing { return .out }
        if hasConcerns { return .flagged }
        switch rsvp {
        case .going: return .available
        case .maybe: return .maybe
        case .noResponse: return .noResponse
        case .notGoing: return .out
        }
    }

    private static func concerns(for playerID: UUID, game: GameEvent, priorGames: [GameEvent]) -> [String] {
        var flags: [String] = []

        if let checkIn = game.preMatchCheckIns[playerID] {
            if let readiness = checkIn.readiness, readiness <= lowReadinessThreshold {
                flags.append(String(format: "Low readiness (%.1f)", readiness))
            }
            if checkIn.hasPain == true {
                flags.append("Pain reported pre-match")
            }
        }

        // Injury coming out of their most recent game with any check-in data.
        if let lastPlayed = priorGames.first(where: {
            $0.postMatchReflections[playerID] != nil || $0.preMatchCheckIns[playerID] != nil
        }) {
            let hurt = lastPlayed.postMatchReflections[playerID]?.hadInjury == true
                || lastPlayed.preMatchCheckIns[playerID]?.hasPain == true
            if hurt, !flags.contains(where: { $0.hasPrefix("Pain") }) {
                flags.append("Injury flagged last game")
            }
        }

        return flags
    }
}

import Foundation

/// Roster membership reads and the movement intents the time-bounded join
/// unlocks: move a player between teams, guest them up an age group, and roll a
/// season over — all without deleting a player or losing history.
extension AppStore {

    // MARK: - Reads

    /// Active memberships for a team.
    func memberships(inTeam id: UUID, includeEnded: Bool = false) -> [RosterMembership] {
        memberships.filter { $0.teamID == id && (includeEnded || $0.isActive) }
    }

    /// A player's memberships, most recent first.
    func memberships(ofPlayer id: UUID, includeEnded: Bool = true) -> [RosterMembership] {
        memberships
            .filter { $0.playerID == id && (includeEnded || $0.isActive) }
            .sorted { ($0.joinedOn ?? .distantPast) > ($1.joinedOn ?? .distantPast) }
    }

    /// Whether a player currently holds an active membership on a team.
    func isMember(_ playerID: UUID, ofTeam teamID: UUID) -> Bool {
        memberships.contains { $0.playerID == playerID && $0.teamID == teamID && $0.isActive }
    }

    /// The team a player is currently on. When a player is guesting up and holds
    /// two active memberships, the most recently joined wins — a single-team
    /// answer for the many callers that still assume one team.
    func teamID(ofPlayer id: UUID) -> UUID? {
        let active = memberships.filter { $0.playerID == id && $0.isActive }
        let chosen = active.max { ($0.joinedOn ?? .distantPast) < ($1.joinedOn ?? .distantPast) }
        return (chosen ?? memberships.first { $0.playerID == id })?.teamID
    }

    // MARK: - Movement

    /// Opens a membership for a player on a team (no-op if one is already active
    /// there). Used when adding a player and when guesting them onto a second team.
    func addMembership(playerID: UUID, teamID: UUID, on date: Date = Date(),
                       status: RosterStatus = .active) {
        guard players.contains(where: { $0.id == playerID }),
              teams.contains(where: { $0.id == teamID }),
              !isMember(playerID, ofTeam: teamID) else { return }
        memberships.append(RosterMembership(playerID: playerID, teamID: teamID, joinedOn: date, status: status))
    }

    /// Ends a membership (records `leftOn`) rather than deleting it, so the
    /// player's time on that team stays in the history.
    func endMembership(_ membershipID: UUID, on date: Date = Date()) {
        guard let index = memberships.firstIndex(where: { $0.id == membershipID }),
              memberships[index].isActive else { return }
        memberships[index].leftOn = date
    }

    /// Moves a player from their current team(s) to another: ends every active
    /// membership and opens one on the destination. History is preserved; the
    /// player and their evaluation record are untouched.
    func movePlayer(_ playerID: UUID, toTeam newTeamID: UUID, on date: Date = Date()) {
        guard teams.contains(where: { $0.id == newTeamID }) else { return }
        batch {
            for index in memberships.indices where memberships[index].playerID == playerID && memberships[index].isActive {
                memberships[index].leftOn = date
            }
            memberships.append(RosterMembership(playerID: playerID, teamID: newTeamID, joinedOn: date, status: .active))
        }
    }

    /// Guests a player onto a second team while keeping their current one — two
    /// concurrent active memberships (the play-up case).
    func guestPlayer(_ playerID: UUID, ontoTeam teamID: UUID, on date: Date = Date()) {
        addMembership(playerID: playerID, teamID: teamID, on: date, status: .guest)
    }
}

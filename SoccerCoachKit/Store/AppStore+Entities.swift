import Foundation

extension AppStore {
    // MARK: - Attendance & RSVP

    func setAttendance(_ status: AttendanceStatus, for player: Player, in session: TrainingSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].attendance[player.id] = status
    }

    func setAttendance(_ status: AttendanceStatus, for player: Player, in game: GameEvent) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index].attendance[player.id] = status
    }

    func setRSVP(_ status: RSVPStatus, for player: Player, in session: TrainingSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].rsvps[player.id] = status
    }

    func setRSVP(_ status: RSVPStatus, for player: Player, in game: GameEvent) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index].rsvps[player.id] = status
    }

    func setRSVP(_ status: RSVPStatus, for player: Player, in event: TeamEvent) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[index].rsvps[player.id] = status
    }

    // MARK: - Teams

    func setAgeGroup(_ ageGroup: AgeGroup, for team: Team) {
        guard let index = teams.firstIndex(where: { $0.id == team.id }) else { return }
        batch {
            teams[index].ageGroup = ageGroup
            // Keep the minimum-minutes goal within the new game length, so a
            // shorter format doesn't leave every player flagged "at risk".
            teams[index].defaultMinimumMinutes = min(teams[index].defaultMinimumMinutes, ageGroup.defaultGameMinutes)
        }
    }

    func setPeriodFormat(_ format: PeriodFormat, for team: Team) {
        guard let index = teams.firstIndex(where: { $0.id == team.id }) else { return }
        teams[index].periodFormat = format
    }

    func setDefaultMinimumMinutes(_ minutes: Int, for team: Team) {
        guard let index = teams.firstIndex(where: { $0.id == team.id }) else { return }
        teams[index].defaultMinimumMinutes = max(0, minutes)
    }

    func addTeam(name: String, ageGroup: AgeGroup, season: String) {
        let team = Team(id: UUID(), name: name, ageGroup: ageGroup, season: season, accentName: "Teal", trainingDefaults: .standard)
        teams.append(team)
        selectedTeamID = team.id
    }

    func updateTeam(_ team: Team) {
        guard let index = teams.firstIndex(where: { $0.id == team.id }) else { return }
        teams[index] = team
    }

    /// Whether a team can be deleted. The last team can't be removed, since the
    /// app always needs a selected team to display.
    var canDeleteTeam: Bool { teams.count > 1 }

    /// Deletes a team and everything it owns (players, sessions, games, events,
    /// diagrams, and team-specific drills), then reselects another team.
    /// Shared drills (`teamID == nil`) are preserved. No-op on the last team.
    func deleteTeam(_ team: Team) {
        guard canDeleteTeam, teams.contains(where: { $0.id == team.id }) else { return }
        registerUndo("Deleted \(team.name)")

        batch {
            // End this team's memberships. A player guesting on another team
            // keeps that membership and survives; only players left with no team
            // at all are removed — so deleting a team can't delete a play-up kid.
            let teamMemberIDs = Set(memberships.filter { $0.teamID == team.id }.map(\.playerID))
            memberships.removeAll { $0.teamID == team.id }
            let orphanedIDs = teamMemberIDs.filter { pid in !memberships.contains { $0.playerID == pid } }
            formInstances.removeAll { instance in
                (instance.subject.type == .team && instance.subject.id == team.id)
                    || (instance.subject.type == .athlete && (instance.subject.id.map(orphanedIDs.contains) ?? false))
            }
            players.removeAll { orphanedIDs.contains($0.id) }
            sessions.removeAll { $0.teamID == team.id }
            games.removeAll { $0.teamID == team.id }
            events.removeAll { $0.teamID == team.id }
            diagrams.removeAll { $0.teamID == team.id }
            drills.removeAll { $0.teamID == team.id }
            teams.removeAll { $0.id == team.id }

            if selectedTeamID == team.id {
                selectedTeamID = teams.first?.id ?? selectedTeamID
            }
        }
    }

    // MARK: - Players

    /// Adds a player and opens their active membership on a team — the only way
    /// a player enters a roster now that the team link is a time-bounded join.
    func addPlayer(_ player: Player, toTeam teamID: UUID) {
        batch {
            players.append(player)
            memberships.append(RosterMembership(playerID: player.id, teamID: teamID, joinedOn: Date(), status: .active))
        }
    }

    func updatePlayer(_ player: Player) {
        guard let index = players.firstIndex(where: { $0.id == player.id }) else { return }
        players[index] = player
    }

    /// Adds a new development entry or replaces the existing one with the same id.
    func saveDevelopmentEntry(_ entry: DevelopmentEntry, for player: Player) {
        guard let index = players.firstIndex(where: { $0.id == player.id }) else { return }
        if let existing = players[index].developmentLog.firstIndex(where: { $0.id == entry.id }) {
            players[index].developmentLog[existing] = entry
        } else {
            players[index].developmentLog.append(entry)
        }
    }

    func deleteDevelopmentEntry(_ entry: DevelopmentEntry, for player: Player) {
        guard let index = players.firstIndex(where: { $0.id == player.id }) else { return }
        players[index].developmentLog.removeAll { $0.id == entry.id }
    }

    func deletePlayer(_ player: Player) {
        registerUndo("Deleted \(player.name)")
        batch {
            memberships.removeAll { $0.playerID == player.id }
            formInstances.removeAll { $0.subject.type == .athlete && $0.subject.id == player.id }
            players.removeAll { $0.id == player.id }
            sessions = sessions.map { session in
                var updated = session
                updated.attendance.removeValue(forKey: player.id)
                updated.rsvps.removeValue(forKey: player.id)
                return updated
            }
            games = games.map { game in
                var updated = game
                updated.rsvps.removeValue(forKey: player.id)
                updated.attendance.removeValue(forKey: player.id)
                updated.playerReports.removeValue(forKey: player.id)
                return updated
            }
            events = events.map { event in
                var updated = event
                updated.rsvps.removeValue(forKey: player.id)
                return updated
            }
            // Detach any board markers linked to this player so diagrams don't
            // keep a dangling reference (the marker itself stays in place).
            diagrams = diagrams.map { diagram in
                var updated = diagram
                updated.players = updated.players.map { boardPlayer in
                    var marker = boardPlayer
                    if marker.playerID == player.id { marker.playerID = nil }
                    return marker
                }
                return updated
            }
        }
    }

    // MARK: - Games

    func addGame(opponent: String, date: Date, location: String, isHome: Bool, notes: String) {
        games.append(
            GameEvent(
                id: UUID(),
                teamID: selectedTeamID,
                opponent: opponent,
                date: date,
                location: location,
                isHome: isHome,
                notes: notes
            )
        )
    }

    func updateGame(_ game: GameEvent) {
        guard let index = games.firstIndex(where: { $0.id == game.id }) else { return }
        games[index] = game
    }

    func deleteGame(_ game: GameEvent) {
        registerUndo("Deleted game vs \(game.opponent)")
        games.removeAll { $0.id == game.id }
    }

    // MARK: - Team events

    func addEvent(title: String, kind: TeamEventKind, date: Date, endDate: Date?, location: String, notes: String) {
        events.append(
            TeamEvent(
                id: UUID(),
                teamID: selectedTeamID,
                title: title,
                kind: kind,
                date: date,
                endDate: endDate,
                location: location,
                notes: notes
            )
        )
    }

    func updateEvent(_ event: TeamEvent) {
        guard let index = events.firstIndex(where: { $0.id == event.id }) else { return }
        events[index] = event
    }

    func deleteEvent(_ event: TeamEvent) {
        registerUndo("Deleted \(event.title)")
        events.removeAll { $0.id == event.id }
    }

    // MARK: - Drills

    func addDrill(title: String, teamID: UUID?, category: DrillCategory, tags: [String], durationMinutes: Int, equipment: [String], fieldSize: String, fieldSetup: String, coachingPoints: [String], progressions: [String], regressions: [String]) {
        drills.append(
            Drill(
                id: UUID(),
                teamID: teamID,
                title: title,
                category: category,
                tags: tags,
                durationMinutes: durationMinutes,
                equipment: equipment,
                fieldSize: fieldSize,
                fieldSetup: fieldSetup,
                coachingPoints: coachingPoints,
                progressions: progressions,
                regressions: regressions
            )
        )
    }

    func updateDrill(_ drill: Drill) {
        guard let index = drills.firstIndex(where: { $0.id == drill.id }) else { return }
        drills[index] = drill
    }

    /// Soft-deletes a drill: it's hidden from the library but kept in storage so
    /// session blocks referencing it retain their planned content (topic, pitch
    /// area, intensity, diagram, notes) and still resolve for display.
    func deleteDrill(_ drill: Drill) {
        guard let index = drills.firstIndex(where: { $0.id == drill.id }) else { return }
        registerUndo("Removed \(drill.title)")
        // If no session block still references this drill, remove it outright so
        // archived drills don't accumulate; otherwise archive it so those blocks
        // keep their planned content.
        let isReferenced = sessions.contains { $0.blocks.contains { $0.drillID == drill.id } }
        if isReferenced {
            drills[index].isArchived = true
        } else {
            batch {
                drills.remove(at: index)
                diagrams = diagrams.map { diagram in
                    var updated = diagram
                    if updated.drillID == drill.id { updated.drillID = nil }
                    return updated
                }
            }
        }
    }

    // MARK: - Sessions

    func addSession(title: String, date: Date, objective: String, weather: String = "Clear", blocks: [TrainingBlock] = []) {
        sessions.append(
            TrainingSession(
                id: UUID(),
                teamID: selectedTeamID,
                title: title,
                date: date,
                objective: objective,
                weather: weather,
                blocks: blocks,
                attendance: [:]
            )
        )
    }

    func updateSession(_ session: TrainingSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index] = session
    }

    func deleteSession(_ session: TrainingSession) {
        registerUndo("Deleted \(session.title)")
        batch {
            sessions.removeAll { $0.id == session.id }
            diagrams = diagrams.map { diagram in
                var updated = diagram
                if updated.sessionID == session.id {
                    updated.sessionID = nil
                }
                return updated
            }
        }
    }
}

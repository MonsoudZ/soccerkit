import Foundation

extension AppStore {
    // MARK: - Per-team & cross-team lookups

    func players(inTeam id: UUID) -> [Player] {
        let memberIDs = Set(memberships.filter { $0.teamID == id && $0.isActive }.map(\.playerID))
        return players.filter { memberIDs.contains($0.id) }.sorted { $0.number < $1.number }
    }

    func games(inTeam id: UUID) -> [GameEvent] {
        games.filter { $0.teamID == id }.sorted { $0.date < $1.date }
    }

    func sessions(inTeam id: UUID) -> [TrainingSession] {
        sessions.filter { $0.teamID == id }.sorted { $0.date < $1.date }
    }

    func drills(inTeam id: UUID) -> [Drill] {
        drills.filter { !$0.isArchived && ($0.teamID == nil || $0.teamID == id) }
    }

    func nextGame(inTeam id: UUID) -> GameEvent? {
        let scoped = games(inTeam: id)
        return scoped.first { $0.date >= Calendar.current.startOfDay(for: Date()) } ?? scoped.last
    }

    func nextSession(inTeam id: UUID) -> TrainingSession? {
        let scoped = sessions(inTeam: id)
        return scoped.first { $0.date >= Calendar.current.startOfDay(for: Date()) } ?? scoped.last
    }

    /// Earliest upcoming game across every team, if any.
    var soonestGame: GameEvent? {
        games.filter { $0.date >= Calendar.current.startOfDay(for: Date()) }.min { $0.date < $1.date }
    }

    /// Earliest upcoming training across every team, if any.
    var soonestSession: TrainingSession? {
        sessions.filter { $0.date >= Calendar.current.startOfDay(for: Date()) }.min { $0.date < $1.date }
    }

    var teamEvents: [TeamEvent] {
        events
            .filter { $0.teamID == selectedTeamID }
            .sorted { $0.date < $1.date }
    }

    var teamDiagrams: [TacticsDiagram] {
        diagrams
            .filter { $0.teamID == selectedTeamID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    var teamDrills: [Drill] {
        drills
            .filter { !$0.isArchived && ($0.teamID == nil || $0.teamID == selectedTeamID) }
            .sorted { first, second in
                if first.teamID == selectedTeamID && second.teamID == nil { return true }
                if first.teamID == nil && second.teamID == selectedTeamID { return false }
                return first.title < second.title
            }
    }

    var teamDrillTags: [String] {
        Array(Set(teamDrills.flatMap(\.tags))).sorted()
    }

    func drill(for id: UUID) -> Drill? {
        drills.first { $0.id == id }
    }

    func diagram(for id: UUID?) -> TacticsDiagram? {
        guard let id else { return nil }
        return diagrams.first { $0.id == id }
    }

    func teamName(for id: UUID?) -> String {
        guard let id else { return "Shared" }
        return teams.first { $0.id == id }?.name ?? "Team"
    }

    func attendanceSummary(for session: TrainingSession) -> (present: Int, total: Int) {
        attendanceSummary(session.attendance)
    }

    func attendanceSummary(for game: GameEvent) -> (present: Int, total: Int) {
        attendanceSummary(game.attendance)
    }

    func attendanceSummary(_ attendance: [UUID: AttendanceStatus]) -> (present: Int, total: Int) {
        let ids = Set(roster.map(\.id))
        let present = attendance
            .filter { ids.contains($0.key) }
            .filter { $0.value == .present || $0.value == .late }
            .count

        return (present, roster.count)
    }

    func rsvpSummary(_ rsvps: [UUID: RSVPStatus]) -> (going: Int, maybe: Int, notGoing: Int, total: Int) {
        let ids = Set(roster.map(\.id))
        let scoped = rsvps.filter { ids.contains($0.key) }
        let going = scoped.filter { $0.value == .going }.count
        let maybe = scoped.filter { $0.value == .maybe }.count
        let notGoing = scoped.filter { $0.value == .notGoing }.count
        return (going, maybe, notGoing, roster.count)
    }
}

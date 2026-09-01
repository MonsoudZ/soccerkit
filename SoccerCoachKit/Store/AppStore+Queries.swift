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

    // Attendance and RSVP are counted against the roster of the team the fixture
    // belongs to — never `roster`, which is always the *selected* team's. The
    // dashboard shows `soonestGame`/`soonestSession`, which range over every
    // team, so a fixture belonging to another team was being scored against the
    // wrong squad: its own players failed the membership filter, and the total
    // came from a squad they aren't in. Taking the team from the fixture is why
    // these take a `teamID` rather than reading the selection.

    func attendanceSummary(for session: TrainingSession) -> (present: Int, total: Int) {
        attendanceSummary(session.attendance, inTeam: session.teamID)
    }

    func attendanceSummary(for game: GameEvent) -> (present: Int, total: Int) {
        attendanceSummary(game.attendance, inTeam: game.teamID)
    }

    func attendanceSummary(_ attendance: [UUID: AttendanceStatus], inTeam teamID: UUID) -> (present: Int, total: Int) {
        let squad = players(inTeam: teamID)
        let ids = Set(squad.map(\.id))
        let present = attendance
            .filter { ids.contains($0.key) }
            .filter { $0.value == .present || $0.value == .late }
            .count

        return (present, squad.count)
    }

    func rsvpSummary(for session: TrainingSession) -> (going: Int, maybe: Int, notGoing: Int, total: Int) {
        rsvpSummary(session.rsvps, inTeam: session.teamID)
    }

    func rsvpSummary(for game: GameEvent) -> (going: Int, maybe: Int, notGoing: Int, total: Int) {
        rsvpSummary(game.rsvps, inTeam: game.teamID)
    }

    func rsvpSummary(for event: TeamEvent) -> (going: Int, maybe: Int, notGoing: Int, total: Int) {
        rsvpSummary(event.rsvps, inTeam: event.teamID)
    }

    func rsvpSummary(_ rsvps: [UUID: RSVPStatus], inTeam teamID: UUID) -> (going: Int, maybe: Int, notGoing: Int, total: Int) {
        let squad = players(inTeam: teamID)
        let ids = Set(squad.map(\.id))
        let scoped = rsvps.filter { ids.contains($0.key) }
        let going = scoped.filter { $0.value == .going }.count
        let maybe = scoped.filter { $0.value == .maybe }.count
        let notGoing = scoped.filter { $0.value == .notGoing }.count
        return (going, maybe, notGoing, squad.count)
    }
}

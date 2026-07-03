import CoreGraphics
import Foundation

/// App-wide source of truth. Holds the published domain collections and the
/// intents that mutate them, delegating durability to a `PersistenceService`.
final class AppStore: ObservableObject {
    @Published var teams: [Team] {
        didSet { persist() }
    }
    @Published var players: [Player] {
        didSet { persist() }
    }
    @Published var drills: [Drill] {
        didSet { persist() }
    }
    @Published var sessions: [TrainingSession] {
        didSet { persist() }
    }
    @Published var diagrams: [TacticsDiagram] {
        didSet { persist() }
    }
    @Published var games: [GameEvent] {
        didSet { persist() }
    }
    @Published var events: [TeamEvent] {
        didSet { persist() }
    }
    @Published var selectedTeamID: UUID {
        didSet { persist() }
    }

    private let persistence: PersistenceService

    init(snapshot: AppSnapshot, persistence: PersistenceService = UserDefaultsPersistenceService()) {
        self.teams = snapshot.teams
        self.players = snapshot.players
        self.drills = snapshot.drills
        self.sessions = snapshot.sessions
        self.diagrams = snapshot.diagrams
        self.games = snapshot.games
        self.events = snapshot.events
        self.selectedTeamID = snapshot.teams.contains(where: { $0.id == snapshot.selectedTeamID }) ? snapshot.selectedTeamID : (snapshot.teams.first?.id ?? snapshot.selectedTeamID)
        self.persistence = persistence
    }

    /// The store used at launch: persisted snapshot if present and readable,
    /// otherwise sample data. A snapshot that exists but can't be decoded is
    /// backed up (never overwritten) before falling back, so real user data is
    /// recoverable instead of being silently replaced.
    static var storedOrSample: AppStore {
        let persistence = UserDefaultsPersistenceService()
        let snapshot: AppSnapshot

        switch persistence.load() {
        case .success(let loaded) where !loaded.teams.isEmpty:
            snapshot = loaded
        case .success, .empty:
            // Decoded-but-empty or fresh install: safe to seed with sample data.
            snapshot = SampleData.snapshot
        case .corrupt(let data, let error):
            // Preserve the unreadable blob before any save can clobber it.
            persistence.backupCorruptData(data)
            assertionFailure("Could not decode persisted snapshot; backed up under the corrupt-backup key. \(error)")
            snapshot = SampleData.snapshot
        }

        return AppStore(snapshot: snapshot, persistence: persistence)
    }

    // MARK: - Derived collections

    var selectedTeam: Team {
        teams.first(where: { $0.id == selectedTeamID }) ?? teams[0]
    }

    var roster: [Player] {
        players
            .filter { $0.teamID == selectedTeamID }
            .sorted { $0.number < $1.number }
    }

    var teamSessions: [TrainingSession] {
        sessions
            .filter { $0.teamID == selectedTeamID }
            .sorted { $0.date < $1.date }
    }

    var nextSession: TrainingSession? {
        teamSessions.first { $0.date >= Calendar.current.startOfDay(for: Date()) } ?? teamSessions.last
    }

    var teamGames: [GameEvent] {
        games
            .filter { $0.teamID == selectedTeamID }
            .sorted { $0.date < $1.date }
    }

    var nextGame: GameEvent? {
        teamGames.first { $0.date >= Calendar.current.startOfDay(for: Date()) } ?? teamGames.last
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
            .filter { $0.teamID == nil || $0.teamID == selectedTeamID }
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

        batch {
            players.removeAll { $0.teamID == team.id }
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

    func addPlayer(name: String, number: Int, position: PlayerPosition, guardian: String, notes: String) {
        players.append(
            Player(
                id: UUID(),
                teamID: selectedTeamID,
                name: name,
                number: number,
                position: position,
                guardian: guardian,
                notes: notes
            )
        )
    }

    func updatePlayer(_ player: Player) {
        guard let index = players.firstIndex(where: { $0.id == player.id }) else { return }
        players[index] = player
    }

    func deletePlayer(_ player: Player) {
        batch {
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

    func deleteDrill(_ drill: Drill) {
        drills.removeAll { $0.id == drill.id }
        sessions = sessions.map { session in
            var updated = session
            updated.blocks.removeAll { $0.drillID == drill.id }
            return updated
        }
        diagrams = diagrams.map { diagram in
            var updated = diagram
            if updated.drillID == drill.id {
                updated.drillID = nil
            }
            return updated
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
        sessions.removeAll { $0.id == session.id }
        diagrams = diagrams.map { diagram in
            var updated = diagram
            if updated.sessionID == session.id {
                updated.sessionID = nil
            }
            return updated
        }
    }

    // MARK: - Diagrams

    func diagrams(for session: TrainingSession) -> [TacticsDiagram] {
        let sectionDiagramIDs = Set(session.blocks.compactMap(\.diagramID))
        return diagrams
            .filter { $0.sessionID == session.id || sectionDiagramIDs.contains($0.id) }
            .removingDuplicates()
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func diagrams(for drill: Drill) -> [TacticsDiagram] {
        diagrams
            .filter { $0.drillID == drill.id }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func addDiagram(title: String, sessionID: UUID? = nil, drillID: UUID? = nil) -> TacticsDiagram {
        let defaults = defaultBoardPieces(for: selectedTeam)
        let diagram = TacticsDiagram(
            id: UUID(),
            teamID: selectedTeamID,
            title: title,
            notes: "",
            sessionID: sessionID,
            drillID: drillID,
            players: defaults.players,
            zones: defaults.zones,
            lines: [],
            equipment: defaults.equipment,
            updatedAt: Date()
        )
        diagrams.append(diagram)
        return diagram
    }

    func defaultBoardPieces(for team: Team) -> (players: [BoardPlayer], zones: [BoardZone], equipment: [BoardEquipment]) {
        let defaults = team.trainingDefaults
        let teamRoster = players
            .filter { $0.teamID == team.id }
            .sorted { $0.number < $1.number }
        let teamPlayers = Array(teamRoster.prefix(defaults.playerCount)).enumerated().map { index, player in
            BoardPlayer(
                id: UUID(),
                playerID: player.id,
                label: player.name.components(separatedBy: " ").first ?? "Player \(index + 1)",
                number: player.number,
                side: .team,
                position: defaultPlayerPosition(index: index, count: max(defaults.playerCount, 1))
            )
        }

        let fillInPlayers: [BoardPlayer]
        if teamPlayers.count < defaults.playerCount {
            fillInPlayers = (teamPlayers.count..<defaults.playerCount).map { index in
                BoardPlayer(
                    id: UUID(),
                    playerID: nil,
                    label: "Player \(index + 1)",
                    number: nil,
                    side: .team,
                    position: defaultPlayerPosition(index: index, count: max(defaults.playerCount, 1))
                )
            }
        } else {
            fillInPlayers = []
        }

        let opponents = (0..<defaults.opponentCount).map { index in
            BoardPlayer(
                id: UUID(),
                playerID: nil,
                label: "OPP \(index + 1)",
                number: nil,
                side: .opponent,
                position: defaultOpponentPosition(index: index, count: max(defaults.opponentCount, 1))
            )
        }

        let zones = (0..<defaults.zoneCount).map { index in
            BoardZone(
                id: UUID(),
                title: "Zone \(index + 1)",
                rect: CGRect(x: 0.18 + CGFloat(index % 2) * 0.34, y: 0.32 + CGFloat(index / 2) * 0.2, width: 0.28, height: 0.18)
            )
        }

        let equipment = (0..<defaults.coneCount).map { index in
            BoardEquipment(
                id: UUID(),
                label: "Cone \(index + 1)",
                position: defaultConePosition(index: index, count: max(defaults.coneCount, 1))
            )
        }

        return (teamPlayers + fillInPlayers + opponents, zones, equipment)
    }

    func updateDiagram(_ diagram: TacticsDiagram) {
        guard let index = diagrams.firstIndex(where: { $0.id == diagram.id }) else { return }
        var updated = diagram
        updated.updatedAt = Date()
        diagrams[index] = updated
    }

    func duplicateDiagram(_ diagram: TacticsDiagram) -> TacticsDiagram {
        let copy = TacticsDiagram(
            id: UUID(),
            teamID: diagram.teamID,
            title: "\(diagram.title) Copy",
            notes: diagram.notes,
            // A duplicate starts detached, so it doesn't double-attach to the
            // original's session/drill.
            sessionID: nil,
            drillID: nil,
            players: diagram.players,
            zones: diagram.zones,
            lines: diagram.lines,
            equipment: diagram.equipment,
            updatedAt: Date()
        )
        diagrams.append(copy)
        return copy
    }

    func attachDiagram(_ diagram: TacticsDiagram, to sessionID: UUID?) {
        attachDiagram(diagram, sessionID: sessionID, drillID: nil)
    }

    func attachDiagram(_ diagram: TacticsDiagram, toDrillID drillID: UUID?) {
        attachDiagram(diagram, sessionID: nil, drillID: drillID)
    }

    func attachDiagram(_ diagram: TacticsDiagram, sessionID: UUID?, drillID: UUID?) {
        guard let index = diagrams.firstIndex(where: { $0.id == diagram.id }) else { return }
        diagrams[index].sessionID = sessionID
        diagrams[index].drillID = drillID
        diagrams[index].updatedAt = Date()
    }

    func deleteDiagram(_ diagram: TacticsDiagram) {
        diagrams.removeAll { $0.id == diagram.id }
        sessions = sessions.map { session in
            var updated = session
            updated.blocks = updated.blocks.map { block in
                var updatedBlock = block
                if updatedBlock.diagramID == diagram.id {
                    updatedBlock.diagramID = nil
                }
                return updatedBlock
            }
            return updated
        }
    }

    // MARK: - Sample data

    func resetToSampleData() {
        let sample = SampleData.snapshot
        batch {
            teams = sample.teams
            players = sample.players
            drills = sample.drills
            sessions = sample.sessions
            diagrams = sample.diagrams
            games = sample.games
            events = sample.events
            selectedTeamID = sample.selectedTeamID
        }
    }

    // MARK: - Board layout helpers

    private func defaultPlayerPosition(index: Int, count: Int) -> CGPoint {
        let columns = min(max(count, 1), 4)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let column = index % columns
        let row = index / columns
        let x = CGFloat(column + 1) / CGFloat(columns + 1)
        let y = 0.62 + CGFloat(row) * (0.24 / CGFloat(max(rows - 1, 1)))
        return CGPoint(x: x, y: min(y, 0.86))
    }

    private func defaultOpponentPosition(index: Int, count: Int) -> CGPoint {
        let columns = min(max(count, 1), 4)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let column = index % columns
        let row = index / columns
        let x = CGFloat(column + 1) / CGFloat(columns + 1)
        let y = 0.18 + CGFloat(row) * (0.22 / CGFloat(max(rows - 1, 1)))
        return CGPoint(x: x, y: min(y, 0.42))
    }

    private func defaultConePosition(index: Int, count: Int) -> CGPoint {
        let columns = min(max(count, 1), 4)
        let rows = Int(ceil(Double(count) / Double(columns)))
        let column = index % columns
        let row = index / columns
        let x = 0.18 + CGFloat(column) * (0.64 / CGFloat(max(columns - 1, 1)))
        let y = 0.46 + CGFloat(row) * (0.12 / CGFloat(max(rows - 1, 1)))
        return CGPoint(x: x, y: y)
    }

    // MARK: - Persistence

    /// When true, `persist()` is deferred so a multi-collection mutation writes
    /// a single, consistent snapshot instead of several half-updated ones.
    private var isBatchingPersist = false

    /// Groups several mutations into one persisted snapshot. Nested calls are
    /// safe; only the outermost `batch` triggers the final write.
    private func batch(_ work: () -> Void) {
        let wasBatching = isBatchingPersist
        isBatchingPersist = true
        work()
        if !wasBatching {
            isBatchingPersist = false
            persist()
        }
    }

    private func persist() {
        guard !isBatchingPersist else { return }
        persistence.save(
            AppSnapshot(
                teams: teams,
                players: players,
                drills: drills,
                sessions: sessions,
                diagrams: diagrams,
                games: games,
                events: events,
                selectedTeamID: selectedTeamID
            )
        )
    }
}

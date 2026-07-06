import CoreGraphics
import Foundation
import WidgetKit

/// App-wide source of truth. Holds the published domain collections and the
/// intents that mutate them, delegating durability to a `PersistenceService`.
/// `@MainActor` enforces the invariant that all state access happens on the
/// main thread (persistence itself encodes/writes on a background queue).
@MainActor
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
    private let cloudSync: CloudSyncService?

    /// Whether iCloud key-value sync is on. Mirrors the snapshot to iCloud so the
    /// coach's data follows them across devices.
    @Published var cloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cloudSyncEnabled, forKey: "iCloudSyncEnabled")
            cloudSync?.isEnabled = cloudSyncEnabled
            if cloudSyncEnabled {
                cloudSync?.start()
                cloudSync?.save(snapshot)
            } else {
                cloudSync?.stop()
            }
        }
    }

    /// The live game-day session. Held here (app-lifetime) so an in-progress
    /// match survives navigating between sections on any device — including the
    /// iPhone, where the detail view is torn down on section changes. It is not
    /// `@Published`, so its per-second clock updates don't re-render the rest of
    /// the app; `GameDayView` observes it directly.
    let gameDay = GameDayViewModel()

    init(snapshot: AppSnapshot,
         persistence: PersistenceService = UserDefaultsPersistenceService(),
         cloudSync: CloudSyncService? = nil) {
        self.teams = snapshot.teams
        self.players = snapshot.players
        self.drills = snapshot.drills
        self.sessions = snapshot.sessions
        self.diagrams = snapshot.diagrams
        self.games = snapshot.games
        self.events = snapshot.events
        self.selectedTeamID = snapshot.teams.contains(where: { $0.id == snapshot.selectedTeamID }) ? snapshot.selectedTeamID : (snapshot.teams.first?.id ?? snapshot.selectedTeamID)
        self.persistence = persistence
        self.cloudSync = cloudSync
        self.cloudSyncEnabled = cloudSync?.isEnabled ?? false
        publishWidgetData()
        cloudSync?.onRemoteChange = { [weak self] snapshot in
            self?.applyRemoteSnapshot(snapshot)
        }
        cloudSync?.start()
    }

    /// Applies a snapshot pushed from another device. `restore` re-persists
    /// locally and re-mirrors to iCloud (a no-op, since the bytes already match).
    private func applyRemoteSnapshot(_ snapshot: AppSnapshot) {
        restore(snapshot)
    }

    /// The store used at launch: persisted snapshot if present and readable,
    /// otherwise sample data. A snapshot that exists but can't be decoded is
    /// backed up (never overwritten) before falling back, so real user data is
    /// recoverable instead of being silently replaced.
    @MainActor
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

        let syncEnabled = (UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool) ?? true
        let cloudSync = CloudSyncService(enabled: syncEnabled)
        return AppStore(snapshot: snapshot, persistence: persistence, cloudSync: cloudSync)
    }

    /// Synchronously flushes any pending background write. Call when the app is
    /// about to suspend so the latest state is durable before termination.
    func flushPendingWrites() {
        persistence.flushPendingSync()
    }

    // MARK: - Derived collections

    var selectedTeam: Team {
        teams.first(where: { $0.id == selectedTeamID }) ?? teams[0]
    }

    var roster: [Player] { players(inTeam: selectedTeamID) }

    var teamSessions: [TrainingSession] { sessions(inTeam: selectedTeamID) }

    var nextSession: TrainingSession? { nextSession(inTeam: selectedTeamID) }

    var teamGames: [GameEvent] { games(inTeam: selectedTeamID) }

    var nextGame: GameEvent? { nextGame(inTeam: selectedTeamID) }

    // MARK: - Per-team & cross-team lookups

    func players(inTeam id: UUID) -> [Player] {
        players.filter { $0.teamID == id }.sorted { $0.number < $1.number }
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

    func addPlayer(_ player: Player) {
        players.append(player)
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
        batch {
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
    }

    // MARK: - Sample data

    func resetToSampleData() {
        restore(SampleData.snapshot)
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
        // defer guarantees the flag is restored and the batched write happens
        // even if `work` ever starts throwing — never leaving persistence
        // permanently suppressed.
        defer {
            isBatchingPersist = wasBatching
            if !wasBatching { persist() }
        }
        work()
    }

    private var snapshot: AppSnapshot {
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
    }

    private func persist() {
        guard !isBatchingPersist else { return }
        persistence.save(snapshot)
        publishWidgetData()
        cloudSync?.save(snapshot)
    }

    /// Publishes the soonest fixture (across all teams) to the app group and
    /// reloads the Home Screen widget — but only when it actually changed, so
    /// frequent saves don't thrash WidgetKit.
    func publishWidgetData() {
        let fixture: FixtureSnapshot? = soonestGame.map { game in
            let team = teams.first { $0.id == game.teamID }
            return FixtureSnapshot(
                teamName: team?.name ?? "",
                opponent: game.opponent,
                date: game.date,
                location: game.location,
                isHome: game.isHome,
                accentHex: team?.accent.hex ?? "4F46E5"
            )
        }
        guard fixture != WidgetSharedStore.load() else { return }
        WidgetSharedStore.save(fixture)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Backup & restore

    /// Encodes the entire app state as pretty-printed JSON for export/sharing.
    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(snapshot)
    }

    /// Replaces all state from an exported backup. Returns false (leaving the
    /// current state untouched) if the data isn't a valid, non-empty snapshot.
    @discardableResult
    func importData(_ data: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode(AppSnapshot.self, from: data),
              !imported.teams.isEmpty else { return false }
        restore(imported)
        return true
    }

    private func restore(_ snapshot: AppSnapshot) {
        batch {
            teams = snapshot.teams
            players = snapshot.players
            drills = snapshot.drills
            sessions = snapshot.sessions
            diagrams = snapshot.diagrams
            games = snapshot.games
            events = snapshot.events
            selectedTeamID = teams.contains(where: { $0.id == snapshot.selectedTeamID })
                ? snapshot.selectedTeamID
                : (teams.first?.id ?? snapshot.selectedTeamID)
        }
    }

    // MARK: - Onboarding

    /// Replaces all data with a single freshly-created team. Used by onboarding
    /// when a coach chooses to start clean instead of exploring the sample data.
    func startFresh(name: String, ageGroup: AgeGroup, season: String, accent: TeamAccent) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = Team(
            id: UUID(),
            name: trimmed.isEmpty ? "My Team" : trimmed,
            ageGroup: ageGroup,
            season: season,
            accentName: accent.rawValue,
            trainingDefaults: .standard
        )
        restore(AppSnapshot(teams: [team], players: [], drills: [], sessions: [],
                            diagrams: [], games: [], events: [], selectedTeamID: team.id))
    }

    // MARK: - Undo

    /// A short-lived message shown after a delete; `nil` when there's nothing to
    /// undo. The captured snapshot lets any delete (including cascading team
    /// deletes) be reverted as a whole.
    @Published private(set) var undoMessage: String?
    private var undoSnapshot: AppSnapshot?

    /// Snapshots the current state so the next delete can be reverted. Call
    /// *before* the mutation so the removed items are still captured.
    private func registerUndo(_ message: String) {
        undoSnapshot = snapshot
        undoMessage = message
    }

    /// Restores the state captured before the most recent delete.
    func undoLastDelete() {
        guard let undoSnapshot else { return }
        restore(undoSnapshot)
        self.undoSnapshot = nil
        undoMessage = nil
    }

    func dismissUndo() {
        undoSnapshot = nil
        undoMessage = nil
    }

    var hasCorruptBackup: Bool { persistence.corruptBackup() != nil }
    func corruptBackupData() -> Data? { persistence.corruptBackup() }
    func clearCorruptBackup() { persistence.clearCorruptBackup() }
}

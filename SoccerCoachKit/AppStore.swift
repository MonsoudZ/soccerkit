import CoreGraphics
import Foundation

final class AppStore: ObservableObject {
    @Published var teams: [Team] {
        didSet { save() }
    }
    @Published var players: [Player] {
        didSet { save() }
    }
    @Published var drills: [Drill] {
        didSet { save() }
    }
    @Published var sessions: [TrainingSession] {
        didSet { save() }
    }
    @Published var diagrams: [TacticsDiagram] {
        didSet { save() }
    }
    @Published var games: [GameEvent] {
        didSet { save() }
    }
    @Published var events: [TeamEvent] {
        didSet { save() }
    }
    @Published var selectedTeamID: UUID {
        didSet { save() }
    }

    private static let storageKey = "SoccerCoachKit.AppSnapshot.v1"

    init(teams: [Team], players: [Player], drills: [Drill], sessions: [TrainingSession], diagrams: [TacticsDiagram] = [], games: [GameEvent] = [], events: [TeamEvent] = [], selectedTeamID: UUID) {
        self.teams = teams
        self.players = players
        self.drills = drills
        self.sessions = sessions
        self.diagrams = diagrams
        self.games = games
        self.events = events
        self.selectedTeamID = selectedTeamID
    }

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
        let ids = Set(roster.map(\.id))
        let present = session.attendance
            .filter { ids.contains($0.key) }
            .filter { $0.value == .present || $0.value == .late }
            .count

        return (present, roster.count)
    }

    func setAttendance(_ status: AttendanceStatus, for player: Player, in session: TrainingSession) {
        guard let index = sessions.firstIndex(where: { $0.id == session.id }) else { return }
        sessions[index].attendance[player.id] = status
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

    func rsvpSummary(_ rsvps: [UUID: RSVPStatus]) -> (going: Int, maybe: Int, notGoing: Int, total: Int) {
        let ids = Set(roster.map(\.id))
        let scoped = rsvps.filter { ids.contains($0.key) }
        let going = scoped.filter { $0.value == .going }.count
        let maybe = scoped.filter { $0.value == .maybe }.count
        let notGoing = scoped.filter { $0.value == .notGoing }.count
        return (going, maybe, notGoing, roster.count)
    }

    func setAgeGroup(_ ageGroup: AgeGroup, for team: Team) {
        guard let index = teams.firstIndex(where: { $0.id == team.id }) else { return }
        teams[index].ageGroup = ageGroup
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
            return updated
        }
        events = events.map { event in
            var updated = event
            updated.rsvps.removeValue(forKey: player.id)
            return updated
        }
    }

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
            sessionID: diagram.sessionID,
            drillID: diagram.drillID,
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

    func resetToSampleData() {
        let sample = AppStore.sample
        teams = sample.teams
        players = sample.players
        drills = sample.drills
        sessions = sample.sessions
        diagrams = sample.diagrams
        games = sample.games
        events = sample.events
        selectedTeamID = sample.selectedTeamID
    }

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

    private func save() {
        let snapshot = AppSnapshot(
            teams: teams,
            players: players,
            drills: drills,
            sessions: sessions,
            diagrams: diagrams,
            games: games,
            events: events,
            selectedTeamID: selectedTeamID
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    static var storedOrSample: AppStore {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(AppSnapshot.self, from: data),
            !snapshot.teams.isEmpty
        else {
            return sample
        }

        return AppStore(
            teams: snapshot.teams,
            players: snapshot.players,
            drills: snapshot.drills,
            sessions: snapshot.sessions,
            diagrams: snapshot.diagrams,
            games: snapshot.games,
            events: snapshot.events,
            selectedTeamID: snapshot.teams.contains(where: { $0.id == snapshot.selectedTeamID }) ? snapshot.selectedTeamID : snapshot.teams[0].id
        )
    }
}

private struct AppSnapshot: Codable {
    var teams: [Team]
    var players: [Player]
    var drills: [Drill]
    var sessions: [TrainingSession]
    var diagrams: [TacticsDiagram]
    var games: [GameEvent]
    var events: [TeamEvent]
    var selectedTeamID: UUID

    init(teams: [Team], players: [Player], drills: [Drill], sessions: [TrainingSession], diagrams: [TacticsDiagram], games: [GameEvent], events: [TeamEvent], selectedTeamID: UUID) {
        self.teams = teams
        self.players = players
        self.drills = drills
        self.sessions = sessions
        self.diagrams = diagrams
        self.games = games
        self.events = events
        self.selectedTeamID = selectedTeamID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        teams = try container.decode([Team].self, forKey: .teams)
        players = try container.decode([Player].self, forKey: .players)
        drills = try container.decode([Drill].self, forKey: .drills)
        sessions = try container.decode([TrainingSession].self, forKey: .sessions)
        diagrams = try container.decodeIfPresent([TacticsDiagram].self, forKey: .diagrams) ?? []
        games = try container.decodeIfPresent([GameEvent].self, forKey: .games) ?? []
        events = try container.decodeIfPresent([TeamEvent].self, forKey: .events) ?? []
        selectedTeamID = try container.decode(UUID.self, forKey: .selectedTeamID)
    }
}

extension AppStore {
    static var sample: AppStore {
        let u12 = Team(
            id: UUID(uuidString: "B78D1E06-3270-498F-A763-28C26EF5A001")!,
            name: "Northside Falcons",
            ageGroup: .u12,
            season: "Fall 2026",
            accentName: "Teal",
            trainingDefaults: TrainingBoardDefaults(playerCount: 8, opponentCount: 4, coneCount: 10, zoneCount: 1)
        )

        let u10 = Team(
            id: UUID(uuidString: "B78D1E06-3270-498F-A763-28C26EF5A002")!,
            name: "Park United",
            ageGroup: .u10,
            season: "Fall 2026",
            accentName: "Coral",
            trainingDefaults: TrainingBoardDefaults(playerCount: 6, opponentCount: 2, coneCount: 8, zoneCount: 1)
        )

        let players = [
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810001")!, teamID: u12.id, name: "Maya Chen", number: 2, position: .defender, guardian: "Alex Chen", notes: "Excellent recovery speed.", guardianPhone: "555-0142", guardianEmail: "alex.chen@example.com", secondaryContactName: "Jo Chen", secondaryContactPhone: "555-0143", emergencyContactName: "Alex Chen", emergencyContactPhone: "555-0142", emergencyContactRelation: "Parent", allergies: "Peanuts", medicalNotes: "Carries an EpiPen in her kit bag."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810002")!, teamID: u12.id, name: "Sofia Ramirez", number: 7, position: .midfielder, guardian: "Nina Ramirez", notes: "Working on scanning before first touch."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810003")!, teamID: u12.id, name: "Ava Patel", number: 9, position: .forward, guardian: "Dev Patel", notes: "Confident finisher, encourage combination play."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810004")!, teamID: u12.id, name: "Lena Brooks", number: 10, position: .midfielder, guardian: "Morgan Brooks", notes: "Captain this month."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810005")!, teamID: u12.id, name: "Grace Kim", number: 12, position: .goalkeeper, guardian: "Sam Kim", notes: "Add distribution reps every week.", guardianPhone: "555-0188", guardianEmail: "sam.kim@example.com", emergencyContactName: "Pat Kim", emergencyContactPhone: "555-0189", emergencyContactRelation: "Grandparent", allergies: "None", medicalNotes: "Mild asthma - keeps an inhaler on the bench."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810008")!, teamID: u12.id, name: "Nora Allen", number: 14, position: .defender, guardian: "Chris Allen", notes: "Strong 1v1 defender."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810009")!, teamID: u12.id, name: "Zoe Martin", number: 15, position: .midfielder, guardian: "Rae Martin", notes: "Good passing range."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810010")!, teamID: u12.id, name: "Isla Nguyen", number: 17, position: .forward, guardian: "Minh Nguyen", notes: "Encourage defensive pressing."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810011")!, teamID: u12.id, name: "Emma Davis", number: 18, position: .defender, guardian: "Taylor Davis", notes: "Reliable on restarts."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810012")!, teamID: u12.id, name: "Layla Moore", number: 21, position: .midfielder, guardian: "Harper Moore", notes: "Develop left-foot passing."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810013")!, teamID: u12.id, name: "Ruby Scott", number: 23, position: .forward, guardian: "Jordan Scott", notes: "Quick off the mark."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810014")!, teamID: u12.id, name: "Mila Young", number: 24, position: .defender, guardian: "Casey Young", notes: "Learning center back spacing."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810006")!, teamID: u10.id, name: "Noah Wilson", number: 4, position: .defender, guardian: "Jules Wilson", notes: "New to the team."),
            Player(id: UUID(uuidString: "CF7F53FE-A0FD-41E0-A0D7-98FE15810007")!, teamID: u10.id, name: "Eli Carter", number: 8, position: .midfielder, guardian: "Tess Carter", notes: "Loves small-sided games.")
        ]

        let rondo = Drill(
            id: UUID(uuidString: "8FFB1FD1-4244-464F-89D8-4C70E8B00001")!,
            teamID: nil,
            title: "4v1 Rondo",
            category: .technical,
            tags: ["possession", "first touch", "passing"],
            durationMinutes: 12,
            equipment: ["Four cones", "One ball", "Two spare balls"],
            fieldSize: "10x10 yards",
            fieldSetup: "10x10 yard grid, one defender, four attackers.",
            coachingPoints: ["Open body shape", "Pass with pace", "Move after the pass"],
            progressions: ["Limit attackers to two touches", "Add a second defender after five passes"],
            regressions: ["Make the grid larger", "Allow unlimited touches"]
        )

        let finishing = Drill(
            id: UUID(uuidString: "8FFB1FD1-4244-464F-89D8-4C70E8B00002")!,
            teamID: u12.id,
            title: "Wide Service Finishing",
            category: .technical,
            tags: ["finishing", "wide play", "crossing"],
            durationMinutes: 18,
            equipment: ["Cones", "Full-size goal", "Supply of balls", "Bibs"],
            fieldSize: "Penalty area plus wide channels",
            fieldSetup: "Two wide channels, two central finishers, one goalkeeper.",
            coachingPoints: ["Arrive on time", "Attack near and far posts", "Follow rebounds"],
            progressions: ["Add a recovering defender", "Require one-touch finishes"],
            regressions: ["Serve unopposed crosses", "Start finishers closer to goal"]
        )

        let pressureCover = Drill(
            id: UUID(uuidString: "8FFB1FD1-4244-464F-89D8-4C70E8B00003")!,
            teamID: u12.id,
            title: "Pressure and Cover",
            category: .tactical,
            tags: ["defending", "pressure", "cover"],
            durationMinutes: 15,
            equipment: ["Cones", "Two small goals", "Bibs", "Balls"],
            fieldSize: "20x25 yards",
            fieldSetup: "20x25 yard channel with two defenders and three attackers.",
            coachingPoints: ["First defender presses", "Second defender covers angle", "Recover goal side"],
            progressions: ["Add transition goals after a defensive win", "Reduce the channel width"],
            regressions: ["Start attackers from a static pass", "Give defenders an extra recovery player"]
        )

        let game = Drill(
            id: UUID(uuidString: "8FFB1FD1-4244-464F-89D8-4C70E8B00004")!,
            teamID: nil,
            title: "5v5 to End Zones",
            category: .scrimmage,
            tags: ["transition", "width", "small-sided"],
            durationMinutes: 20,
            equipment: ["Cones", "Bibs", "Balls"],
            fieldSize: "Half field",
            fieldSetup: "Half field, two end zones, score by receiving in the zone.",
            coachingPoints: ["Create width", "Look forward first", "Transition quickly"],
            progressions: ["Score must come from a third-player run", "Limit neutral players to one touch"],
            regressions: ["Add neutral support players", "Increase end-zone depth"]
        )

        let attendance: [UUID: AttendanceStatus] = [
            players[0].id: .present,
            players[1].id: .present,
            players[2].id: .late,
            players[3].id: .excused,
            players[4].id: .present
        ]

        let session = TrainingSession(
            id: UUID(uuidString: "A81EE2E0-46A5-408D-9A93-9AE0AF870001")!,
            teamID: u12.id,
            title: "Building Through Midfield",
            date: Calendar.current.date(byAdding: .day, value: 2, to: Date()) ?? Date(),
            objective: "Improve first touch, support angles, and quick transitions after winning the ball.",
            blocks: [
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900001")!, drillID: rondo.id, minutes: 12, focus: "First touch away from pressure"),
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900002")!, drillID: pressureCover.id, minutes: 15, focus: "Win it, connect the next pass"),
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900003")!, drillID: game.id, minutes: 20, focus: "Use width to break pressure")
            ],
            attendance: attendance
        )

        let secondSession = TrainingSession(
            id: UUID(uuidString: "A81EE2E0-46A5-408D-9A93-9AE0AF870002")!,
            teamID: u12.id,
            title: "Final Third Decisions",
            date: Calendar.current.date(byAdding: .day, value: 6, to: Date()) ?? Date(),
            objective: "Help attackers choose between shooting, crossing, and recycling possession.",
            blocks: [
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900004")!, drillID: rondo.id, minutes: 10, focus: "Fast rhythm"),
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900005")!, drillID: finishing.id, minutes: 18, focus: "Timing runs into the box"),
                TrainingBlock(id: UUID(uuidString: "C5800DE5-D1CF-43AD-9C37-F0F61F900006")!, drillID: game.id, minutes: 22, focus: "Reward correct final pass")
            ],
            attendance: [:]
        )

        let leagueGame = GameEvent(
            id: UUID(uuidString: "F19C4A70-1B2C-4E55-9A10-6B7C8D9E0001")!,
            teamID: u12.id,
            opponent: "Riverside Rovers",
            date: Calendar.current.date(byAdding: .day, value: 4, to: Date()) ?? Date(),
            location: "Central Park Field 3",
            isHome: true,
            notes: "League fixture. Arrive 45 minutes early for warm-up.",
            rsvps: [
                players[0].id: .going,
                players[1].id: .going,
                players[2].id: .maybe,
                players[3].id: .notGoing,
                players[4].id: .going
            ]
        )

        let awayGame = GameEvent(
            id: UUID(uuidString: "F19C4A70-1B2C-4E55-9A10-6B7C8D9E0002")!,
            teamID: u12.id,
            opponent: "Hilltop Hawks",
            date: Calendar.current.date(byAdding: .day, value: 11, to: Date()) ?? Date(),
            location: "Hilltop Sports Complex",
            isHome: false,
            notes: "Carpool sign-up to follow.",
            rsvps: [:]
        )

        let tournament = TeamEvent(
            id: UUID(uuidString: "D53A9C11-77E4-4B2A-9F0E-2C4A6B8D0001")!,
            teamID: u12.id,
            title: "Fall Classic Cup",
            kind: .tournament,
            date: Calendar.current.date(byAdding: .day, value: 18, to: Date()) ?? Date(),
            endDate: Calendar.current.date(byAdding: .day, value: 19, to: Date()) ?? Date(),
            location: "Riverside Tournament Grounds",
            notes: "Three group games Saturday, knockout rounds Sunday. Bring both kits.",
            rsvps: [
                players[0].id: .going,
                players[1].id: .going,
                players[2].id: .going,
                players[3].id: .maybe
            ]
        )

        let teamSocial = TeamEvent(
            id: UUID(uuidString: "D53A9C11-77E4-4B2A-9F0E-2C4A6B8D0002")!,
            teamID: u12.id,
            title: "End of Season Pizza Night",
            kind: .social,
            date: Calendar.current.date(byAdding: .day, value: 25, to: Date()) ?? Date(),
            location: "Mario's Pizzeria",
            notes: "Awards and team photo. Families welcome."
        )

        return AppStore(
            teams: [u12, u10],
            players: players,
            drills: [rondo, finishing, pressureCover, game],
            sessions: [session, secondSession],
            games: [leagueGame, awayGame],
            events: [tournament, teamSocial],
            selectedTeamID: u12.id
        )
    }
}

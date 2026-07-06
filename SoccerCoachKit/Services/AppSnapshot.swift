import Foundation

/// A Codable value type capturing the entire persisted state of the app.
/// The `PersistenceService` reads and writes snapshots; `AppStore` projects
/// them into its published collections.
struct AppSnapshot: Codable {
    /// Bump when the persisted shape changes in a way older code can't read, so
    /// future loads can migrate an old blob instead of failing to decode it.
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    /// A monotonically increasing edit counter used for iCloud conflict
    /// resolution: a remote snapshot is adopted only if its `dataVersion` is
    /// higher than the local one, so newest-wins is deterministic rather than
    /// depending on upload order.
    var dataVersion: Int
    var teams: [Team]
    var players: [Player]
    var drills: [Drill]
    var sessions: [TrainingSession]
    var diagrams: [TacticsDiagram]
    var games: [GameEvent]
    var events: [TeamEvent]
    var selectedTeamID: UUID

    init(teams: [Team], players: [Player], drills: [Drill], sessions: [TrainingSession], diagrams: [TacticsDiagram], games: [GameEvent], events: [TeamEvent], selectedTeamID: UUID, schemaVersion: Int = AppSnapshot.currentSchemaVersion, dataVersion: Int = 0) {
        self.schemaVersion = schemaVersion
        self.dataVersion = dataVersion
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
        // Absent in pre-versioning blobs; those are schema v1 by definition.
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        dataVersion = try container.decodeIfPresent(Int.self, forKey: .dataVersion) ?? 0
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

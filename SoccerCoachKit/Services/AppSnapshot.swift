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
    /// The time-bounded player↔team joins that replaced `Player.teamID`. A
    /// pre-membership snapshot (or a player still carrying a legacy team seed)
    /// is migrated into memberships at construction, so old data never loses its
    /// roster links.
    var memberships: [RosterMembership]
    /// User/org-owned evaluation templates. Built-in templates live in code
    /// (`FormTemplateCatalog`) and are intentionally not persisted here, so they
    /// always match the app version. Empty until a coach saves a custom form.
    var formTemplates: [FormTemplate]
    /// Filled-in evaluation responses — the generic engine's data. Every scored
    /// flow (pre/post-game, development, tryout, coach review) accretes here
    /// instead of onto a per-entity dictionary.
    var formInstances: [FormInstance]

    init(teams: [Team], players: [Player], drills: [Drill], sessions: [TrainingSession], diagrams: [TacticsDiagram], games: [GameEvent], events: [TeamEvent], selectedTeamID: UUID, memberships: [RosterMembership] = [], formTemplates: [FormTemplate] = [], formInstances: [FormInstance] = [], schemaVersion: Int = AppSnapshot.currentSchemaVersion, dataVersion: Int = 0) {
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
        self.memberships = Self.migratingMemberships(players: players, existing: memberships)
        self.formTemplates = formTemplates
        self.formInstances = formInstances
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
        // Absent in blobs saved before the evaluation engine landed; those
        // simply have no custom templates or responses yet.
        formTemplates = try container.decodeIfPresent([FormTemplate].self, forKey: .formTemplates) ?? []
        formInstances = try container.decodeIfPresent([FormInstance].self, forKey: .formInstances) ?? []
        let storedMemberships = try container.decodeIfPresent([RosterMembership].self, forKey: .memberships) ?? []
        memberships = Self.migratingMemberships(players: players, existing: storedMemberships)
    }

    /// Ensures every player has a roster membership: keeps the ones already
    /// present and synthesizes one (from a player's `legacyTeamID`) for any that
    /// predate the membership model. A runtime player has no legacy seed, so this
    /// is a no-op on the live snapshot path — it only fires for migrated data.
    private static func migratingMemberships(players: [Player], existing: [RosterMembership]) -> [RosterMembership] {
        var memberships = existing
        let represented = Set(existing.map(\.playerID))
        for player in players where !represented.contains(player.id) {
            guard let teamID = player.legacyTeamID else { continue }
            // Deterministic id (= player id) so two devices migrating the same
            // old snapshot converge on one membership rather than duplicating.
            memberships.append(RosterMembership(id: player.id, playerID: player.id, teamID: teamID, status: .active))
        }
        return memberships
    }
}

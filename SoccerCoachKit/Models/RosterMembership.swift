import Foundation

/// A player's standing on a team's roster.
enum RosterStatus: String, CaseIterable, Identifiable, Codable {
    case active     // full-time squad member
    case guest      // playing up / guesting from another team
    case injured    // on the roster but currently unavailable
    case inactive   // temporarily not participating

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .guest: return "Guest"
        case .injured: return "Injured"
        case .inactive: return "Inactive"
        }
    }
}

/// The time-bounded join between a player and a team — the replacement for the
/// old `Player.teamID` column, and the load-bearing seam of the whole design.
///
/// A player never *belongs* to a team; they hold a membership with a start and
/// (maybe) an end date. That single change unlocks the movement stories the flat
/// column made impossible:
///
/// - **Move between teams** → end one membership (`leftOn = today`), open another.
///   Full history preserved, nothing deleted.
/// - **Play up an age group** → hold two concurrent active memberships (their own
///   team and the one they guest for). Falls out for free.
/// - **Season rollover** → close last season's memberships, open new ones; the
///   player and their entire evaluation history carry across untouched.
///
/// `jerseyNumber`/`position` are per-team overrides, reserved for when identity
/// moves onto `Person`; until then they're `nil` and `Player.number`/`.position`
/// remain the source of truth.
struct RosterMembership: Identifiable, Hashable, Codable {
    let id: UUID
    var playerID: UUID
    var teamID: UUID
    /// When the player joined this team. `nil` for data migrated from the flat
    /// `teamID` column, where the join date was never recorded.
    var joinedOn: Date?
    /// When the player left. `nil` = still on the team (an active membership).
    var leftOn: Date?
    var status: RosterStatus
    /// Per-team jersey override; `nil` falls back to `Player.number`.
    var jerseyNumber: Int?
    /// Per-team position override; `nil` falls back to `Player.position`.
    var position: PlayerPosition?

    init(id: UUID = UUID(), playerID: UUID, teamID: UUID, joinedOn: Date? = nil,
         leftOn: Date? = nil, status: RosterStatus = .active,
         jerseyNumber: Int? = nil, position: PlayerPosition? = nil) {
        self.id = id
        self.playerID = playerID
        self.teamID = teamID
        self.joinedOn = joinedOn
        self.leftOn = leftOn
        self.status = status
        self.jerseyNumber = jerseyNumber
        self.position = position
    }

    /// True while the player is still on this team (no end date recorded).
    var isActive: Bool { leftOn == nil }

    enum CodingKeys: String, CodingKey {
        case id, playerID, teamID, joinedOn, leftOn, status, jerseyNumber, position
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        playerID = try c.decode(UUID.self, forKey: .playerID)
        teamID = try c.decode(UUID.self, forKey: .teamID)
        joinedOn = try c.decodeIfPresent(Date.self, forKey: .joinedOn)
        leftOn = try c.decodeIfPresent(Date.self, forKey: .leftOn)
        status = try c.decodeIfPresent(RosterStatus.self, forKey: .status) ?? .active
        jerseyNumber = try c.decodeIfPresent(Int.self, forKey: .jerseyNumber)
        position = try c.decodeIfPresent(PlayerPosition.self, forKey: .position)
    }
}

import Foundation

struct Team: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var ageGroup: AgeGroup
    var season: String
    var accentName: String
    var trainingDefaults: TrainingBoardDefaults
    /// Whether matches are split into halves or quarters (independent of age).
    var periodFormat: PeriodFormat
    /// Team-wide minimum minutes each player should get, unless a player
    /// overrides it. Zero disables the goal.
    var defaultMinimumMinutes: Int
    /// The organization that owns this team. Defaults to the personal org, so
    /// "org is never optional" holds without changing any construction site.
    var organizationID: UUID

    init(
        id: UUID,
        name: String,
        ageGroup: AgeGroup,
        season: String,
        accentName: String,
        trainingDefaults: TrainingBoardDefaults = .standard,
        periodFormat: PeriodFormat? = nil,
        defaultMinimumMinutes: Int? = nil,
        organizationID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.ageGroup = ageGroup
        self.season = season
        self.accentName = accentName
        self.trainingDefaults = trainingDefaults
        self.periodFormat = periodFormat ?? .default(for: ageGroup)
        self.defaultMinimumMinutes = defaultMinimumMinutes ?? ageGroup.defaultGameMinutes / 2
        self.organizationID = organizationID ?? Organization.personalID
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ageGroup
        case season
        case accentName
        case trainingDefaults
        case periodFormat
        case defaultMinimumMinutes
        case organizationID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ageGroup = try container.decode(AgeGroup.self, forKey: .ageGroup)
        season = try container.decode(String.self, forKey: .season)
        accentName = try container.decode(String.self, forKey: .accentName)
        trainingDefaults = try container.decodeIfPresent(TrainingBoardDefaults.self, forKey: .trainingDefaults) ?? .standard
        periodFormat = try container.decodeIfPresent(PeriodFormat.self, forKey: .periodFormat) ?? .default(for: ageGroup)
        defaultMinimumMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultMinimumMinutes) ?? ageGroup.defaultGameMinutes / 2
        // Pre-org blobs default to the personal organization.
        organizationID = try container.decodeIfPresent(UUID.self, forKey: .organizationID) ?? Organization.personalID
    }
}

struct TrainingBoardDefaults: Hashable, Codable {
    var playerCount: Int
    var opponentCount: Int
    var coneCount: Int
    var zoneCount: Int

    static let standard = TrainingBoardDefaults(playerCount: 6, opponentCount: 0, coneCount: 8, zoneCount: 1)
}

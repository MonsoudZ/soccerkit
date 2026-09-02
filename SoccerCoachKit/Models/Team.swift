import Foundation

struct Team: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    /// The age group exactly as stored, which may be a value this build does not know:
    /// a newer build writes one, sync hands it to this one, and last-write-wins means
    /// whatever we encode next is what every device ends up with. Keeping the raw string
    /// is what stops an older build from quietly rewriting a U7 team as U6 the next time
    /// its name is edited.
    private var storedAgeGroup: String
    /// The age group as this build understands it, falling back to the nearest band we
    /// do know (see `AgeGroup.nearestKnown(to:)`). Setting it stores the new value
    /// verbatim, so an explicit choice by a coach is never rounded.
    var ageGroup: AgeGroup {
        get { AgeGroup(rawValue: storedAgeGroup) ?? .nearestKnown(to: storedAgeGroup) }
        set { storedAgeGroup = newValue.rawValue }
    }
    /// What to show the coach: the stored label, which is the truth even when the
    /// rulebook beside it is an approximation.
    var ageGroupLabel: String { storedAgeGroup }
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
        self.storedAgeGroup = ageGroup.rawValue
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
        // Decoded as a string, not as the enum. Every other field here is tolerant of
        // data an *older* build wrote; this is the one that has to be tolerant of data a
        // *newer* build wrote, because a value outside this build's cases would throw
        // and take the whole team with it. SyncWireCodec already refuses to let an
        // unknown record type crash an older client, and that guard stops at the type —
        // it does not reach inside the payload.
        storedAgeGroup = try container.decode(String.self, forKey: .ageGroup)
        let group = AgeGroup(rawValue: storedAgeGroup) ?? .nearestKnown(to: storedAgeGroup)
        season = try container.decode(String.self, forKey: .season)
        accentName = try container.decode(String.self, forKey: .accentName)
        trainingDefaults = try container.decodeIfPresent(TrainingBoardDefaults.self, forKey: .trainingDefaults) ?? .standard
        periodFormat = try container.decodeIfPresent(PeriodFormat.self, forKey: .periodFormat) ?? .default(for: group)
        defaultMinimumMinutes = try container.decodeIfPresent(Int.self, forKey: .defaultMinimumMinutes) ?? group.defaultGameMinutes / 2
        // Pre-org blobs default to the personal organization.
        organizationID = try container.decodeIfPresent(UUID.self, forKey: .organizationID) ?? Organization.personalID
    }

    /// Written by hand because `storedAgeGroup` and its coding key differ, and because
    /// the point of the pair is that what goes back out is what came in.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(storedAgeGroup, forKey: .ageGroup)
        try container.encode(season, forKey: .season)
        try container.encode(accentName, forKey: .accentName)
        try container.encode(trainingDefaults, forKey: .trainingDefaults)
        try container.encode(periodFormat, forKey: .periodFormat)
        try container.encode(defaultMinimumMinutes, forKey: .defaultMinimumMinutes)
        try container.encode(organizationID, forKey: .organizationID)
    }
}

struct TrainingBoardDefaults: Hashable, Codable {
    var playerCount: Int
    var opponentCount: Int
    var coneCount: Int
    var zoneCount: Int

    static let standard = TrainingBoardDefaults(playerCount: 6, opponentCount: 0, coneCount: 8, zoneCount: 1)
}

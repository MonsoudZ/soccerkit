import Foundation

struct Drill: Identifiable, Hashable, Codable {
    let id: UUID
    var teamID: UUID?
    var title: String
    /// The category exactly as stored, which may be a value this build does not know —
    /// the same reasoning as `Team.storedAgeGroup`. A newer build writes one, sync hands
    /// it to this one, and last-write-wins means whatever we encode next is what every
    /// device ends up with. Keeping the raw string stops an older build from quietly
    /// rewriting a newer category as "Technical" the next time the drill is edited.
    private var storedCategory: String
    var tags: [String]
    var durationMinutes: Int
    var equipment: [String]
    var fieldSize: String
    var fieldSetup: String
    var coachingPoints: [String]
    var progressions: [String]
    var regressions: [String]
    /// Soft-delete flag. An archived drill is hidden from the library but still
    /// resolvable, so session blocks that reference it keep their full content.
    var isArchived: Bool

    /// The category as this build understands it, falling back to Technical for a value
    /// it does not know. Setting it stores the new value verbatim, so a coach's explicit
    /// choice is never rounded.
    var category: DrillCategory {
        get { DrillCategory(rawValue: storedCategory) ?? .technical }
        set { storedCategory = newValue.rawValue }
    }

    /// What to show the coach: the stored label, which is the truth even when this build
    /// has no case for it.
    var categoryLabel: String { storedCategory }

    init(id: UUID, teamID: UUID? = nil, title: String, category: DrillCategory, tags: [String] = [], durationMinutes: Int, equipment: [String] = [], fieldSize: String = "", fieldSetup: String, coachingPoints: [String], progressions: [String] = [], regressions: [String] = [], isArchived: Bool = false) {
        self.id = id
        self.teamID = teamID
        self.title = title
        self.storedCategory = category.rawValue
        self.tags = tags
        self.durationMinutes = durationMinutes
        self.equipment = equipment
        self.fieldSize = fieldSize
        self.fieldSetup = fieldSetup
        self.coachingPoints = coachingPoints
        self.progressions = progressions
        self.regressions = regressions
        self.isArchived = isArchived
    }

    enum CodingKeys: String, CodingKey {
        case id
        case teamID
        case title
        case category
        case tags
        case durationMinutes
        case equipment
        case fieldSize
        case fieldSetup
        case coachingPoints
        case progressions
        case regressions
        case isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        teamID = try container.decodeIfPresent(UUID.self, forKey: .teamID)
        title = try container.decode(String.self, forKey: .title)
        // Everything below `title` is optional now, and the reason is the REST API: a
        // drill created there carries a name and a description and nothing else, because
        // that is all POST /drills collects. Requiring a category or a duration meant a
        // drill made on the web could not be decoded at all, and Codable loses the whole
        // record over one missing key — so it never reached the phone. A blank the coach
        // can fill in beats a drill that silently does not arrive.
        storedCategory = try container.decodeIfPresent(String.self, forKey: .category)
            ?? DrillCategory.technical.rawValue
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
        equipment = try container.decodeIfPresent([String].self, forKey: .equipment) ?? []
        fieldSize = try container.decodeIfPresent(String.self, forKey: .fieldSize) ?? ""
        fieldSetup = try container.decodeIfPresent(String.self, forKey: .fieldSetup) ?? ""
        coachingPoints = try container.decodeIfPresent([String].self, forKey: .coachingPoints) ?? []
        progressions = try container.decodeIfPresent([String].self, forKey: .progressions) ?? []
        regressions = try container.decodeIfPresent([String].self, forKey: .regressions) ?? []
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
    }

    /// Written by hand for the reason `Team`'s is: `storedCategory` and its coding key
    /// differ, and the point of the pair is that what goes back out is what came in.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(teamID, forKey: .teamID)
        try container.encode(title, forKey: .title)
        try container.encode(storedCategory, forKey: .category)
        try container.encode(tags, forKey: .tags)
        try container.encode(durationMinutes, forKey: .durationMinutes)
        try container.encode(equipment, forKey: .equipment)
        try container.encode(fieldSize, forKey: .fieldSize)
        try container.encode(fieldSetup, forKey: .fieldSetup)
        try container.encode(coachingPoints, forKey: .coachingPoints)
        try container.encode(progressions, forKey: .progressions)
        try container.encode(regressions, forKey: .regressions)
        try container.encode(isArchived, forKey: .isArchived)
    }
}

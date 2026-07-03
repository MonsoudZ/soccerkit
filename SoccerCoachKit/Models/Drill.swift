import Foundation

struct Drill: Identifiable, Hashable, Codable {
    let id: UUID
    var teamID: UUID?
    var title: String
    var category: DrillCategory
    var tags: [String]
    var durationMinutes: Int
    var equipment: [String]
    var fieldSize: String
    var fieldSetup: String
    var coachingPoints: [String]
    var progressions: [String]
    var regressions: [String]

    init(id: UUID, teamID: UUID? = nil, title: String, category: DrillCategory, tags: [String] = [], durationMinutes: Int, equipment: [String] = [], fieldSize: String = "", fieldSetup: String, coachingPoints: [String], progressions: [String] = [], regressions: [String] = []) {
        self.id = id
        self.teamID = teamID
        self.title = title
        self.category = category
        self.tags = tags
        self.durationMinutes = durationMinutes
        self.equipment = equipment
        self.fieldSize = fieldSize
        self.fieldSetup = fieldSetup
        self.coachingPoints = coachingPoints
        self.progressions = progressions
        self.regressions = regressions
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
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        teamID = try container.decodeIfPresent(UUID.self, forKey: .teamID)
        title = try container.decode(String.self, forKey: .title)
        category = try container.decode(DrillCategory.self, forKey: .category)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        durationMinutes = try container.decode(Int.self, forKey: .durationMinutes)
        equipment = try container.decodeIfPresent([String].self, forKey: .equipment) ?? []
        fieldSize = try container.decodeIfPresent(String.self, forKey: .fieldSize) ?? ""
        fieldSetup = try container.decode(String.self, forKey: .fieldSetup)
        coachingPoints = try container.decode([String].self, forKey: .coachingPoints)
        progressions = try container.decodeIfPresent([String].self, forKey: .progressions) ?? []
        regressions = try container.decodeIfPresent([String].self, forKey: .regressions) ?? []
    }
}

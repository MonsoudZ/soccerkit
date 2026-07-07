import CoreGraphics
import Foundation

struct BoardPlayer: Identifiable, Hashable, Codable {
    let id: UUID
    var playerID: UUID?
    var label: String
    var number: Int?
    var side: BoardSide
    var position: CGPoint
}

struct BoardZone: Identifiable, Hashable, Codable {
    let id: UUID
    var title: String
    var rect: CGRect
}

struct BoardLine: Identifiable, Hashable, Codable {
    let id: UUID
    var start: CGPoint
    var end: CGPoint
}

struct BoardEquipment: Identifiable, Hashable, Codable {
    let id: UUID
    var label: String
    var position: CGPoint
}

struct TacticsDiagram: Identifiable, Hashable, Codable {
    let id: UUID
    var teamID: UUID
    var title: String
    var notes: String
    var sessionID: UUID?
    var drillID: UUID?
    /// A scheduled game this diagram is the plan for; `nil` when unattached.
    var gameID: UUID?
    var players: [BoardPlayer]
    var zones: [BoardZone]
    var lines: [BoardLine]
    var equipment: [BoardEquipment]
    var updatedAt: Date

    init(id: UUID, teamID: UUID, title: String, notes: String, sessionID: UUID?, drillID: UUID? = nil, gameID: UUID? = nil, players: [BoardPlayer], zones: [BoardZone], lines: [BoardLine], equipment: [BoardEquipment] = [], updatedAt: Date) {
        self.id = id
        self.teamID = teamID
        self.title = title
        self.notes = notes
        self.sessionID = sessionID
        self.drillID = drillID
        self.gameID = gameID
        self.players = players
        self.zones = zones
        self.lines = lines
        self.equipment = equipment
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case teamID
        case title
        case notes
        case sessionID
        case drillID
        case gameID
        case players
        case zones
        case lines
        case equipment
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        teamID = try container.decode(UUID.self, forKey: .teamID)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decode(String.self, forKey: .notes)
        sessionID = try container.decodeIfPresent(UUID.self, forKey: .sessionID)
        drillID = try container.decodeIfPresent(UUID.self, forKey: .drillID)
        gameID = try container.decodeIfPresent(UUID.self, forKey: .gameID)
        players = try container.decode([BoardPlayer].self, forKey: .players)
        zones = try container.decode([BoardZone].self, forKey: .zones)
        lines = try container.decode([BoardLine].self, forKey: .lines)
        equipment = try container.decodeIfPresent([BoardEquipment].self, forKey: .equipment) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

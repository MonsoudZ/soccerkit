import Foundation

struct GameEvent: Identifiable, Hashable, Codable {
    let id: UUID
    var teamID: UUID
    var opponent: String
    var date: Date
    var location: String
    var isHome: Bool
    var notes: String
    var rsvps: [UUID: RSVPStatus]

    init(id: UUID, teamID: UUID, opponent: String, date: Date, location: String = "", isHome: Bool = true, notes: String = "", rsvps: [UUID: RSVPStatus] = [:]) {
        self.id = id
        self.teamID = teamID
        self.opponent = opponent
        self.date = date
        self.location = location
        self.isHome = isHome
        self.notes = notes
        self.rsvps = rsvps
    }

    enum CodingKeys: String, CodingKey {
        case id
        case teamID
        case opponent
        case date
        case location
        case isHome
        case notes
        case rsvps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        teamID = try container.decode(UUID.self, forKey: .teamID)
        opponent = try container.decode(String.self, forKey: .opponent)
        date = try container.decode(Date.self, forKey: .date)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        isHome = try container.decodeIfPresent(Bool.self, forKey: .isHome) ?? true
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        rsvps = try container.decodeIfPresent([UUID: RSVPStatus].self, forKey: .rsvps) ?? [:]
    }
}

import Foundation

struct TeamEvent: Identifiable, Hashable, Codable {
    let id: UUID
    var teamID: UUID
    var title: String
    var kind: TeamEventKind
    var date: Date
    var endDate: Date?
    var location: String
    var notes: String
    var rsvps: [UUID: RSVPStatus]

    init(id: UUID, teamID: UUID, title: String, kind: TeamEventKind, date: Date, endDate: Date? = nil, location: String = "", notes: String = "", rsvps: [UUID: RSVPStatus] = [:]) {
        self.id = id
        self.teamID = teamID
        self.title = title
        self.kind = kind
        self.date = date
        self.endDate = endDate
        self.location = location
        self.notes = notes
        self.rsvps = rsvps
    }

    /// A multi-day event (for example a weekend tournament) has an end date after the start day.
    var isMultiDay: Bool {
        guard let endDate else { return false }
        return Calendar.current.startOfDay(for: endDate) > Calendar.current.startOfDay(for: date)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case teamID
        case title
        case kind
        case date
        case endDate
        case location
        case notes
        case rsvps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        teamID = try container.decode(UUID.self, forKey: .teamID)
        title = try container.decode(String.self, forKey: .title)
        kind = try container.decodeIfPresent(TeamEventKind.self, forKey: .kind) ?? .other
        date = try container.decode(Date.self, forKey: .date)
        endDate = try container.decodeIfPresent(Date.self, forKey: .endDate)
        location = try container.decodeIfPresent(String.self, forKey: .location) ?? ""
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        rsvps = try container.decodeIfPresent([UUID: RSVPStatus].self, forKey: .rsvps) ?? [:]
    }
}

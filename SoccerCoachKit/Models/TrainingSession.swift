import Foundation

struct TrainingBlock: Identifiable, Hashable, Codable {
    let id: UUID
    var drillID: UUID
    var minutes: Int
    var focus: String
    var diagramID: UUID?
    var topic: String
    var positions: [PlayerPosition]
    var pitchArea: String
    var details: String
    var intensity: Int

    init(id: UUID, drillID: UUID, minutes: Int, focus: String, diagramID: UUID? = nil, topic: String = "", positions: [PlayerPosition] = [], pitchArea: String = "", details: String = "", intensity: Int = 3) {
        self.id = id
        self.drillID = drillID
        self.minutes = minutes
        self.focus = focus
        self.diagramID = diagramID
        self.topic = topic.isEmpty ? focus : topic
        self.positions = positions
        self.pitchArea = pitchArea
        self.details = details
        self.intensity = intensity
    }

    enum CodingKeys: String, CodingKey {
        case id
        case drillID
        case minutes
        case focus
        case diagramID
        case topic
        case positions
        case pitchArea
        case details
        case intensity
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        drillID = try container.decode(UUID.self, forKey: .drillID)
        minutes = try container.decode(Int.self, forKey: .minutes)
        focus = try container.decode(String.self, forKey: .focus)
        diagramID = try container.decodeIfPresent(UUID.self, forKey: .diagramID)
        topic = try container.decodeIfPresent(String.self, forKey: .topic) ?? focus
        positions = try container.decodeIfPresent([PlayerPosition].self, forKey: .positions) ?? []
        pitchArea = try container.decodeIfPresent(String.self, forKey: .pitchArea) ?? ""
        details = try container.decodeIfPresent(String.self, forKey: .details) ?? ""
        intensity = try container.decodeIfPresent(Int.self, forKey: .intensity) ?? 3
    }
}

struct TrainingSession: Identifiable, Hashable, Codable {
    let id: UUID
    var teamID: UUID
    var title: String
    var date: Date
    var objective: String
    var weather: String
    var blocks: [TrainingBlock]
    var attendance: [UUID: AttendanceStatus]
    var rsvps: [UUID: RSVPStatus]

    init(id: UUID, teamID: UUID, title: String, date: Date, objective: String, weather: String = "Clear", blocks: [TrainingBlock], attendance: [UUID: AttendanceStatus], rsvps: [UUID: RSVPStatus] = [:]) {
        self.id = id
        self.teamID = teamID
        self.title = title
        self.date = date
        self.objective = objective
        self.weather = weather
        self.blocks = blocks
        self.attendance = attendance
        self.rsvps = rsvps
    }

    enum CodingKeys: String, CodingKey {
        case id
        case teamID
        case title
        case date
        case objective
        case weather
        case blocks
        case attendance
        case rsvps
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        teamID = try container.decode(UUID.self, forKey: .teamID)
        title = try container.decode(String.self, forKey: .title)
        date = try container.decode(Date.self, forKey: .date)
        objective = try container.decode(String.self, forKey: .objective)
        weather = try container.decodeIfPresent(String.self, forKey: .weather) ?? "Clear"
        blocks = try container.decode([TrainingBlock].self, forKey: .blocks)
        attendance = try container.decodeIfPresent([UUID: AttendanceStatus].self, forKey: .attendance) ?? [:]
        rsvps = try container.decodeIfPresent([UUID: RSVPStatus].self, forKey: .rsvps) ?? [:]
    }
}

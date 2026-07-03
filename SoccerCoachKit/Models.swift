import CoreGraphics
import Foundation

enum PlayerPosition: String, CaseIterable, Identifiable, Codable {
    case goalkeeper = "GK"
    case defender = "DEF"
    case midfielder = "MID"
    case forward = "FWD"

    var id: String { rawValue }
}

enum AttendanceStatus: String, CaseIterable, Identifiable, Codable {
    case present = "Present"
    case late = "Late"
    case excused = "Excused"
    case absent = "Absent"

    var id: String { rawValue }
}

enum RSVPStatus: String, CaseIterable, Identifiable, Codable {
    case going = "Going"
    case maybe = "Maybe"
    case notGoing = "Not Going"
    case noResponse = "No Response"

    var id: String { rawValue }
}

enum DrillCategory: String, CaseIterable, Identifiable, Codable {
    case warmup = "Warm-up"
    case technical = "Technical"
    case tactical = "Tactical"
    case conditioning = "Conditioning"
    case scrimmage = "Scrimmage"

    var id: String { rawValue }
}

enum AgeGroup: String, CaseIterable, Identifiable, Codable {
    case u6 = "U6"
    case u8 = "U8"
    case u10 = "U10"
    case u12 = "U12"
    case u14 = "U14"
    case u16 = "U16"
    case u19 = "U19"

    var id: String { rawValue }

    var playersOnField: Int {
        switch self {
        case .u6, .u8: return 4
        case .u10: return 7
        case .u12: return 9
        case .u14, .u16, .u19: return 11
        }
    }

    var maxRosterSize: Int {
        switch self {
        case .u6: return 8
        case .u8: return 10
        case .u10: return 12
        case .u12: return 16
        case .u14, .u16, .u19: return 18
        }
    }

    var defaultGameMinutes: Int {
        switch self {
        case .u6: return 24
        case .u8: return 40
        case .u10: return 50
        case .u12: return 60
        case .u14: return 70
        case .u16, .u19: return 80
        }
    }
}

struct Team: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var ageGroup: AgeGroup
    var season: String
    var accentName: String
    var trainingDefaults: TrainingBoardDefaults

    init(id: UUID, name: String, ageGroup: AgeGroup, season: String, accentName: String, trainingDefaults: TrainingBoardDefaults = .standard) {
        self.id = id
        self.name = name
        self.ageGroup = ageGroup
        self.season = season
        self.accentName = accentName
        self.trainingDefaults = trainingDefaults
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ageGroup
        case season
        case accentName
        case trainingDefaults
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        ageGroup = try container.decode(AgeGroup.self, forKey: .ageGroup)
        season = try container.decode(String.self, forKey: .season)
        accentName = try container.decode(String.self, forKey: .accentName)
        trainingDefaults = try container.decodeIfPresent(TrainingBoardDefaults.self, forKey: .trainingDefaults) ?? .standard
    }
}

struct TrainingBoardDefaults: Hashable, Codable {
    var playerCount: Int
    var opponentCount: Int
    var coneCount: Int
    var zoneCount: Int

    static let standard = TrainingBoardDefaults(playerCount: 6, opponentCount: 0, coneCount: 8, zoneCount: 1)
}

struct Player: Identifiable, Hashable, Codable {
    let id: UUID
    var teamID: UUID
    var name: String
    var number: Int
    var position: PlayerPosition
    var guardian: String
    var notes: String
    var guardianPhone: String
    var guardianEmail: String
    var secondaryContactName: String
    var secondaryContactPhone: String
    var emergencyContactName: String
    var emergencyContactPhone: String
    var emergencyContactRelation: String
    var allergies: String
    var medicalNotes: String

    init(
        id: UUID,
        teamID: UUID,
        name: String,
        number: Int,
        position: PlayerPosition,
        guardian: String,
        notes: String,
        guardianPhone: String = "",
        guardianEmail: String = "",
        secondaryContactName: String = "",
        secondaryContactPhone: String = "",
        emergencyContactName: String = "",
        emergencyContactPhone: String = "",
        emergencyContactRelation: String = "",
        allergies: String = "",
        medicalNotes: String = ""
    ) {
        self.id = id
        self.teamID = teamID
        self.name = name
        self.number = number
        self.position = position
        self.guardian = guardian
        self.notes = notes
        self.guardianPhone = guardianPhone
        self.guardianEmail = guardianEmail
        self.secondaryContactName = secondaryContactName
        self.secondaryContactPhone = secondaryContactPhone
        self.emergencyContactName = emergencyContactName
        self.emergencyContactPhone = emergencyContactPhone
        self.emergencyContactRelation = emergencyContactRelation
        self.allergies = allergies
        self.medicalNotes = medicalNotes
    }

    enum CodingKeys: String, CodingKey {
        case id
        case teamID
        case name
        case number
        case position
        case guardian
        case notes
        case guardianPhone
        case guardianEmail
        case secondaryContactName
        case secondaryContactPhone
        case emergencyContactName
        case emergencyContactPhone
        case emergencyContactRelation
        case allergies
        case medicalNotes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        teamID = try container.decode(UUID.self, forKey: .teamID)
        name = try container.decode(String.self, forKey: .name)
        number = try container.decode(Int.self, forKey: .number)
        position = try container.decode(PlayerPosition.self, forKey: .position)
        guardian = try container.decode(String.self, forKey: .guardian)
        notes = try container.decode(String.self, forKey: .notes)
        guardianPhone = try container.decodeIfPresent(String.self, forKey: .guardianPhone) ?? ""
        guardianEmail = try container.decodeIfPresent(String.self, forKey: .guardianEmail) ?? ""
        secondaryContactName = try container.decodeIfPresent(String.self, forKey: .secondaryContactName) ?? ""
        secondaryContactPhone = try container.decodeIfPresent(String.self, forKey: .secondaryContactPhone) ?? ""
        emergencyContactName = try container.decodeIfPresent(String.self, forKey: .emergencyContactName) ?? ""
        emergencyContactPhone = try container.decodeIfPresent(String.self, forKey: .emergencyContactPhone) ?? ""
        emergencyContactRelation = try container.decodeIfPresent(String.self, forKey: .emergencyContactRelation) ?? ""
        allergies = try container.decodeIfPresent(String.self, forKey: .allergies) ?? ""
        medicalNotes = try container.decodeIfPresent(String.self, forKey: .medicalNotes) ?? ""
    }
}

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
        attendance = try container.decode([UUID: AttendanceStatus].self, forKey: .attendance)
        rsvps = try container.decodeIfPresent([UUID: RSVPStatus].self, forKey: .rsvps) ?? [:]
    }
}

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

enum BoardSide: String, Codable {
    case team
    case opponent
}

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
    var players: [BoardPlayer]
    var zones: [BoardZone]
    var lines: [BoardLine]
    var equipment: [BoardEquipment]
    var updatedAt: Date

    init(id: UUID, teamID: UUID, title: String, notes: String, sessionID: UUID?, drillID: UUID? = nil, players: [BoardPlayer], zones: [BoardZone], lines: [BoardLine], equipment: [BoardEquipment] = [], updatedAt: Date) {
        self.id = id
        self.teamID = teamID
        self.title = title
        self.notes = notes
        self.sessionID = sessionID
        self.drillID = drillID
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
        players = try container.decode([BoardPlayer].self, forKey: .players)
        zones = try container.decode([BoardZone].self, forKey: .zones)
        lines = try container.decode([BoardLine].self, forKey: .lines)
        equipment = try container.decodeIfPresent([BoardEquipment].self, forKey: .equipment) ?? []
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

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

enum PeriodFormat: String, CaseIterable, Identifiable, Codable {
    case halves = "Halves"
    case quarters = "Quarters"

    var id: String { rawValue }

    var periodCount: Int {
        switch self {
        case .halves: return 2
        case .quarters: return 4
        }
    }

    /// Common youth convention, used as the initial value when a team is created.
    static func `default`(for ageGroup: AgeGroup) -> PeriodFormat {
        switch ageGroup {
        case .u6, .u8, .u10: return .quarters
        default: return .halves
        }
    }

    /// Short label for a 1-based period index (e.g. H1/H2 or Q1–Q4, OT beyond).
    func label(forPeriod period: Int) -> String {
        let prefix = self == .halves ? "H" : "Q"
        return period <= periodCount ? "\(prefix)\(period)" : "OT\(period - periodCount)"
    }
}

enum TeamEventKind: String, CaseIterable, Identifiable, Codable {
    case tournament = "Tournament"
    case scrimmage = "Scrimmage"
    case social = "Team Event"
    case meeting = "Meeting"
    case other = "Other"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .tournament: return "trophy"
        case .scrimmage: return "sportscourt"
        case .social: return "party.popper"
        case .meeting: return "person.2.wave.2"
        case .other: return "calendar"
        }
    }
}

enum BoardSide: String, Codable {
    case team
    case opponent
}

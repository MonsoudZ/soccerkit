import Foundation

enum PlayerPosition: String, CaseIterable, Identifiable, Codable {
    case goalkeeper = "GK"
    case defender = "DEF"
    case midfielder = "MID"
    case forward = "FWD"

    var id: String { rawValue }

    /// Spelled-out name (used for accessibility, where "GK" reads poorly).
    var displayName: String {
        switch self {
        case .goalkeeper: return "Goalkeeper"
        case .defender: return "Defender"
        case .midfielder: return "Midfielder"
        case .forward: return "Forward"
        }
    }
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

/// A single-year age group, as US Soccer registers them.
///
/// Every year from U6 to U19 is here rather than the even bands the app started
/// with, because the standards don't move in twos: U9 and U10 play 7v7 with a
/// build-out line while U11 plays 9v9 without one, and heading opens up at U12.
/// A coach on a band had to round to the wrong rulebook.
///
/// The raw values are the ones already persisted, so existing teams keep their
/// age group across this change; the odd years are additions.
///
/// Everything derived lives in `standard` (see `USSoccerStandard`); the
/// properties here read from it so call sites didn't have to change.
enum AgeGroup: String, CaseIterable, Identifiable, Codable {
    case u6 = "U6"
    case u7 = "U7"
    case u8 = "U8"
    case u9 = "U9"
    case u10 = "U10"
    case u11 = "U11"
    case u12 = "U12"
    case u13 = "U13"
    case u14 = "U14"
    case u15 = "U15"
    case u16 = "U16"
    case u17 = "U17"
    case u18 = "U18"
    case u19 = "U19"

    var id: String { rawValue }

    var playersOnField: Int { standard.playersPerSide }

    var maxRosterSize: Int { standard.maxRosterSize }

    var defaultGameMinutes: Int { standard.gameMinutes }
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

    /// The initial value when a team is created, taken from the age group's US
    /// Soccer standard: 4v4 is played in quarters, everything from 7v7 up in
    /// halves. A coach can still choose either — the period format is a team
    /// setting, not a rule.
    static func `default`(for ageGroup: AgeGroup) -> PeriodFormat {
        ageGroup.standard.periodCount == 4 ? .quarters : .halves
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

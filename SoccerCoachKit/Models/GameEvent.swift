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
    /// Actual attendance recorded on game day, keyed by player id.
    var attendance: [UUID: AttendanceStatus]
    /// Final score once the game is played; `nil` until recorded.
    var teamScore: Int?
    var opponentScore: Int?
    /// Per-player post-game reports, keyed by player id.
    var playerReports: [UUID: GamePlayerReport]
    /// Per-player pre-match readiness check-ins, keyed by player id.
    var preMatchCheckIns: [UUID: PreMatchCheckIn]
    /// Per-player post-match reflections, keyed by player id.
    var postMatchReflections: [UUID: PostMatchReflection]
    /// The coach's pre-match plan for the team.
    var coachPreMatch: CoachPreMatchPlan
    /// The coach's post-match review of the team.
    var coachPostMatch: CoachPostMatchReview

    init(id: UUID, teamID: UUID, opponent: String, date: Date, location: String = "", isHome: Bool = true, notes: String = "", rsvps: [UUID: RSVPStatus] = [:], attendance: [UUID: AttendanceStatus] = [:], teamScore: Int? = nil, opponentScore: Int? = nil, playerReports: [UUID: GamePlayerReport] = [:], preMatchCheckIns: [UUID: PreMatchCheckIn] = [:], postMatchReflections: [UUID: PostMatchReflection] = [:], coachPreMatch: CoachPreMatchPlan = .init(), coachPostMatch: CoachPostMatchReview = .init()) {
        self.id = id
        self.teamID = teamID
        self.opponent = opponent
        self.date = date
        self.location = location
        self.isHome = isHome
        self.notes = notes
        self.rsvps = rsvps
        self.attendance = attendance
        self.teamScore = teamScore
        self.opponentScore = opponentScore
        self.playerReports = playerReports
        self.preMatchCheckIns = preMatchCheckIns
        self.postMatchReflections = postMatchReflections
        self.coachPreMatch = coachPreMatch
        self.coachPostMatch = coachPostMatch
    }

    /// This game with every trace of a player removed.
    ///
    /// A game keys five separate dictionaries by player id, and the delete
    /// cascade used to clear them by hand at the call site — so when the
    /// questionnaires feature added `preMatchCheckIns` and
    /// `postMatchReflections`, the cascade wasn't extended and a deleted player's
    /// wellness answers (sleep, mood, pain, injury) survived on every game they
    /// were recorded in, exported and synced with the rest. Removal lives here
    /// now, beside the dictionaries themselves, so a sixth one is handled by the
    /// same method rather than by remembering.
    func removingPlayer(_ playerID: UUID) -> GameEvent {
        var updated = self
        updated.rsvps.removeValue(forKey: playerID)
        updated.attendance.removeValue(forKey: playerID)
        updated.playerReports.removeValue(forKey: playerID)
        updated.preMatchCheckIns.removeValue(forKey: playerID)
        updated.postMatchReflections.removeValue(forKey: playerID)
        return updated
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
        case attendance
        case teamScore
        case opponentScore
        case playerReports
        case preMatchCheckIns
        case postMatchReflections
        case coachPreMatch
        case coachPostMatch
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
        attendance = try container.decodeIfPresent([UUID: AttendanceStatus].self, forKey: .attendance) ?? [:]
        teamScore = try container.decodeIfPresent(Int.self, forKey: .teamScore)
        opponentScore = try container.decodeIfPresent(Int.self, forKey: .opponentScore)
        playerReports = try container.decodeIfPresent([UUID: GamePlayerReport].self, forKey: .playerReports) ?? [:]
        preMatchCheckIns = try container.decodeIfPresent([UUID: PreMatchCheckIn].self, forKey: .preMatchCheckIns) ?? [:]
        postMatchReflections = try container.decodeIfPresent([UUID: PostMatchReflection].self, forKey: .postMatchReflections) ?? [:]
        coachPreMatch = try container.decodeIfPresent(CoachPreMatchPlan.self, forKey: .coachPreMatch) ?? .init()
        coachPostMatch = try container.decodeIfPresent(CoachPostMatchReview.self, forKey: .coachPostMatch) ?? .init()
    }

    /// Win/Loss/Draw once a score is recorded.
    var resultLabel: String? {
        guard let teamScore, let opponentScore else { return nil }
        if teamScore > opponentScore { return "Win" }
        if teamScore < opponentScore { return "Loss" }
        return "Draw"
    }
}

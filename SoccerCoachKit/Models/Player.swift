import Foundation

struct Player: Identifiable, Hashable, Codable {
    let id: UUID
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
    /// Per-player override of the team's minimum-minutes goal. `nil` means the
    /// player uses the team default.
    var minMinutesOverride: Int?
    /// Dated development records (notes + skill ratings), oldest-to-newest as added.
    var developmentLog: [DevelopmentEntry]

    /// A team id carried only for migration: the player's team is now a
    /// time-bounded `RosterMembership`, not a column here. Set from the
    /// initializer's `teamID:` seed or decoded from a pre-membership snapshot's
    /// old `teamID` key, then used once (in `AppSnapshot`) to synthesize the
    /// first membership. Never encoded — the column is gone.
    let legacyTeamID: UUID?

    init(
        id: UUID,
        teamID: UUID? = nil,
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
        medicalNotes: String = "",
        minMinutesOverride: Int? = nil,
        developmentLog: [DevelopmentEntry] = []
    ) {
        self.id = id
        self.legacyTeamID = teamID
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
        self.minMinutesOverride = minMinutesOverride
        self.developmentLog = developmentLog
    }

    /// A spoken summary for VoiceOver on roster rows.
    var accessibilityLabel: String {
        var parts = [name, "number \(number)", position.displayName]
        if !guardian.isEmpty { parts.append("guardian \(guardian)") }
        return parts.joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case id
        // Decoded (not encoded) so a pre-RosterMembership snapshot's team link
        // is migrated rather than lost.
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
        case minMinutesOverride
        case developmentLog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        legacyTeamID = try container.decodeIfPresent(UUID.self, forKey: .teamID)
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
        minMinutesOverride = try container.decodeIfPresent(Int.self, forKey: .minMinutesOverride)
        developmentLog = try container.decodeIfPresent([DevelopmentEntry].self, forKey: .developmentLog) ?? []
    }

    /// Explicit encoder so the retired `teamID` (and the transient
    /// `legacyTeamID`) are never written back — the team link lives only in
    /// `RosterMembership` now.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(number, forKey: .number)
        try container.encode(position, forKey: .position)
        try container.encode(guardian, forKey: .guardian)
        try container.encode(notes, forKey: .notes)
        try container.encode(guardianPhone, forKey: .guardianPhone)
        try container.encode(guardianEmail, forKey: .guardianEmail)
        try container.encode(secondaryContactName, forKey: .secondaryContactName)
        try container.encode(secondaryContactPhone, forKey: .secondaryContactPhone)
        try container.encode(emergencyContactName, forKey: .emergencyContactName)
        try container.encode(emergencyContactPhone, forKey: .emergencyContactPhone)
        try container.encode(emergencyContactRelation, forKey: .emergencyContactRelation)
        try container.encode(allergies, forKey: .allergies)
        try container.encode(medicalNotes, forKey: .medicalNotes)
        try container.encodeIfPresent(minMinutesOverride, forKey: .minMinutesOverride)
        try container.encode(developmentLog, forKey: .developmentLog)
    }
}

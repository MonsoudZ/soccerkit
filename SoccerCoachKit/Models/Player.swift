import Foundation

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
    /// Per-player override of the team's minimum-minutes goal. `nil` means the
    /// player uses the team default.
    var minMinutesOverride: Int?

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
        medicalNotes: String = "",
        minMinutesOverride: Int? = nil
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
        self.minMinutesOverride = minMinutesOverride
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
        case minMinutesOverride
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
        minMinutesOverride = try container.decodeIfPresent(Int.self, forKey: .minMinutesOverride)
    }
}

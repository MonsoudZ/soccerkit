import Foundation

/// A human — the identity that exists independently of any team or login.
///
/// This is the doc's second load-bearing seam: `Person ≠ UserAccount`. A U9
/// player is a `Person` with no login; a parent is a `Person` with one. Contact
/// and medical details live here because they're true of the human regardless of
/// which team(s) they play on or which season it is.
///
/// For now every `Player` has a 1:1 `Person` (auto-kept-in-sync by the store),
/// so nothing in the app has to read `Person` yet — but the entity, the link,
/// and the migration all exist, so the parent/player tiers and cross-season
/// identity are additive rather than a rewrite later.
struct Person: Identifiable, Hashable, Codable {
    let id: UUID
    var name: String
    var guardian: String
    var guardianPhone: String
    var guardianEmail: String
    var secondaryContactName: String
    var secondaryContactPhone: String
    var emergencyContactName: String
    var emergencyContactPhone: String
    var emergencyContactRelation: String
    var allergies: String
    var medicalNotes: String

    init(id: UUID, name: String, guardian: String = "", guardianPhone: String = "",
         guardianEmail: String = "", secondaryContactName: String = "", secondaryContactPhone: String = "",
         emergencyContactName: String = "", emergencyContactPhone: String = "",
         emergencyContactRelation: String = "", allergies: String = "", medicalNotes: String = "") {
        self.id = id
        self.name = name
        self.guardian = guardian
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

    /// Namespace for deriving the coach's Person id from their Apple user id.
    /// MUST match the backend's coachPersonNamespace verbatim, so the account
    /// Person and the synced Person are one identity across every device.
    static let coachIDNamespace = UUID(uuidString: "2b6f0cc9-04e9-4c8e-8f1a-7c3d5e2a9b40")!

    /// The coach's stable Person id, derived from their Apple user id (which
    /// equals the backend's identity-token `sub`). Deterministic — never random —
    /// so the same coach maps to the same Person on the server and every device.
    static func coachID(forAppleUserID appleUserID: String) -> UUID {
        UUID.v5(namespace: coachIDNamespace, name: appleUserID)
    }

    enum CodingKeys: String, CodingKey {
        case id, name, guardian, guardianPhone, guardianEmail, secondaryContactName,
             secondaryContactPhone, emergencyContactName, emergencyContactPhone,
             emergencyContactRelation, allergies, medicalNotes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        guardian = try c.decodeIfPresent(String.self, forKey: .guardian) ?? ""
        guardianPhone = try c.decodeIfPresent(String.self, forKey: .guardianPhone) ?? ""
        guardianEmail = try c.decodeIfPresent(String.self, forKey: .guardianEmail) ?? ""
        secondaryContactName = try c.decodeIfPresent(String.self, forKey: .secondaryContactName) ?? ""
        secondaryContactPhone = try c.decodeIfPresent(String.self, forKey: .secondaryContactPhone) ?? ""
        emergencyContactName = try c.decodeIfPresent(String.self, forKey: .emergencyContactName) ?? ""
        emergencyContactPhone = try c.decodeIfPresent(String.self, forKey: .emergencyContactPhone) ?? ""
        emergencyContactRelation = try c.decodeIfPresent(String.self, forKey: .emergencyContactRelation) ?? ""
        allergies = try c.decodeIfPresent(String.self, forKey: .allergies) ?? ""
        medicalNotes = try c.decodeIfPresent(String.self, forKey: .medicalNotes) ?? ""
    }
}

/// An authenticatable identity, optional per `Person`. Parents and coaches have
/// one; young players usually don't. Sign in with Apple maps here — the same
/// flow `AuthController` runs today, now with a server-side home for the
/// identity. `personID` is a nullable owner: an account can exist before it's
/// linked to the Person it represents (e.g. a coach before their own Person row
/// is created with the org tier).
struct UserAccount: Identifiable, Hashable, Codable {
    let id: UUID
    /// The Person this account authenticates as; `nil` until linked.
    var personID: UUID?
    /// Stable Sign in with Apple user identifier.
    var appleUserID: String
    var displayName: String?

    init(id: UUID = UUID(), personID: UUID? = nil, appleUserID: String, displayName: String? = nil) {
        self.id = id
        self.personID = personID
        self.appleUserID = appleUserID
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey { case id, personID, appleUserID, displayName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        personID = try c.decodeIfPresent(UUID.self, forKey: .personID)
        appleUserID = try c.decode(String.self, forKey: .appleUserID)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
    }
}

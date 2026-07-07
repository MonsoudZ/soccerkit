import Foundation

/// The tenant boundary. A solo coach gets a **personal** org auto-created; a
/// club is the same row with `kind: club`. Nothing on the hot path asks "is this
/// a club" — it queries memberships. Making the org never-optional (every team
/// belongs to one) is the seam that lets "solo coach" and "50-team club" be the
/// same schema.
struct Organization: Identifiable, Hashable, Codable {
    /// The single personal organization for this local install. Teams default to
    /// it, so "org is never optional" holds without any construction-site churn.
    static let personalID = UUID(uuidString: "0A9A0000-0000-0000-0000-000000000001")!

    let id: UUID
    var name: String
    var kind: OrgKind

    init(id: UUID = UUID(), name: String, kind: OrgKind) {
        self.id = id
        self.name = name
        self.kind = kind
    }

    /// The auto-created personal org every install has until a real club exists.
    static let personal = Organization(id: personalID, name: "My Coaching", kind: .personal)

    enum CodingKeys: String, CodingKey { case id, name, kind }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decodeIfPresent(OrgKind.self, forKey: .kind) ?? .personal
    }
}

enum OrgKind: String, CaseIterable, Identifiable, Codable {
    case personal
    case club

    var id: String { rawValue }
}

/// The roles a Person can hold within an organization. A person can hold several
/// (the solo coach owner holds admin + director + coach; a parent who also
/// coaches holds parent + coach). Never a column on a user — always this join.
enum OrgRole: String, CaseIterable, Identifiable, Codable {
    case admin
    case director
    case coach
    case parent
    case player

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .director: return "Director"
        case .coach: return "Coach"
        case .parent: return "Parent"
        case .player: return "Player"
        }
    }
}

/// `(person_id, organization_id, roles)` — how a human participates in an org.
/// Named `OrgMembership` to stay distinct from `RosterMembership` (the
/// player↔team join). Roles are a set so one row covers the owner's
/// admin+director+coach.
struct OrgMembership: Identifiable, Hashable, Codable {
    let id: UUID
    var personID: UUID
    var organizationID: UUID
    var roles: Set<OrgRole>

    init(id: UUID = UUID(), personID: UUID, organizationID: UUID, roles: Set<OrgRole>) {
        self.id = id
        self.personID = personID
        self.organizationID = organizationID
        self.roles = roles
    }

    func hasRole(_ role: OrgRole) -> Bool { roles.contains(role) }

    enum CodingKeys: String, CodingKey { case id, personID, organizationID, roles }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        personID = try c.decode(UUID.self, forKey: .personID)
        organizationID = try c.decode(UUID.self, forKey: .organizationID)
        roles = try c.decodeIfPresent(Set<OrgRole>.self, forKey: .roles) ?? []
    }
}

import Foundation

/// The kinds of thing that can be shared. Polymorphic so one table covers
/// coach-to-coach session sharing, a shared drill library, tactics diagrams, and
/// whatever comes next — without a new join per type.
enum ShareableType: String, CaseIterable, Identifiable, Codable {
    case session
    case drill
    case diagram
    case formTemplate

    var id: String { rawValue }
}

/// How widely a shared thing reaches.
enum ShareScope: String, CaseIterable, Identifiable, Codable {
    case privateOnly = "private" // only the author (the default; nothing shared)
    case team                    // everyone on the team
    case org                     // the whole organization (a club library)
    case link                    // anyone with the link

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .privateOnly: return "Private"
        case .team: return "Team"
        case .org: return "Organization"
        case .link: return "Link"
        }
    }
}

/// `(shareable_type, shareable_id, scope, granted_by, expires_at)` — the entire
/// "share sessions between coaches / access what other coaches made for you /
/// club library" feature as one polymorphic, scoped row. A club library is just
/// "everything with an `org`-scoped grant in this organization." Even while
/// Phase 1 only ever writes `private`, the column exists so `team`/`org`/`link`
/// are config, not a schema change.
struct ShareGrant: Identifiable, Hashable, Codable {
    let id: UUID
    var shareableType: ShareableType
    var shareableID: UUID
    var scope: ShareScope
    /// The organization the grant reaches into (for `org` scope); the owner's
    /// personal org otherwise.
    var organizationID: UUID
    /// The Person who granted the share; `nil` for pre-accounts data.
    var grantedBy: UUID?
    var expiresAt: Date?

    init(id: UUID = UUID(), shareableType: ShareableType, shareableID: UUID,
         scope: ShareScope = .privateOnly, organizationID: UUID = Organization.personalID,
         grantedBy: UUID? = nil, expiresAt: Date? = nil) {
        self.id = id
        self.shareableType = shareableType
        self.shareableID = shareableID
        self.scope = scope
        self.organizationID = organizationID
        self.grantedBy = grantedBy
        self.expiresAt = expiresAt
    }

    /// Whether the grant is currently in force (not expired).
    func isActive(asOf now: Date) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt > now
    }

    enum CodingKeys: String, CodingKey {
        case id, shareableType, shareableID, scope, organizationID, grantedBy, expiresAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        shareableType = try c.decode(ShareableType.self, forKey: .shareableType)
        shareableID = try c.decode(UUID.self, forKey: .shareableID)
        scope = try c.decodeIfPresent(ShareScope.self, forKey: .scope) ?? .privateOnly
        organizationID = try c.decodeIfPresent(UUID.self, forKey: .organizationID) ?? Organization.personalID
        grantedBy = try c.decodeIfPresent(UUID.self, forKey: .grantedBy)
        expiresAt = try c.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}

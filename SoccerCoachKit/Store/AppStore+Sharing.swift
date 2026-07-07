import Foundation

/// Reads and mutations over the polymorphic `ShareGrant` table. Phase 1 only
/// ever leaves things `private` (no grant), but the scopes are here so
/// coach-to-coach sharing and a club library are config, not a schema change.
extension AppStore {

    /// The grant for a shareable, if one exists (absent = private).
    func shareGrant(forType type: ShareableType, id: UUID) -> ShareGrant? {
        shareGrants.first { $0.shareableType == type && $0.shareableID == id }
    }

    /// The effective scope of a shareable (private when there's no grant).
    func shareScope(ofType type: ShareableType, id: UUID) -> ShareScope {
        shareGrant(forType: type, id: id)?.scope ?? .privateOnly
    }

    /// Sets how widely a shareable is shared. `private` removes any grant;
    /// anything else upserts a single grant for that shareable.
    func setShareScope(_ scope: ShareScope, forType type: ShareableType, id: UUID,
                       in organizationID: UUID? = nil, grantedBy: UUID? = nil, expiresAt: Date? = nil) {
        guard scope != .privateOnly else {
            stopSharing(type: type, id: id)
            return
        }
        let org = organizationID ?? Organization.personalID
        if let index = shareGrants.firstIndex(where: { $0.shareableType == type && $0.shareableID == id }) {
            // Reuse the existing grant id so it updates rather than duplicates.
            shareGrants[index] = ShareGrant(id: shareGrants[index].id, shareableType: type, shareableID: id,
                                            scope: scope, organizationID: org, grantedBy: grantedBy, expiresAt: expiresAt)
        } else {
            shareGrants.append(ShareGrant(shareableType: type, shareableID: id, scope: scope,
                                          organizationID: org, grantedBy: grantedBy, expiresAt: expiresAt))
        }
    }

    /// Returns a shareable to private by dropping its grant.
    func stopSharing(type: ShareableType, id: UUID) {
        shareGrants.removeAll { $0.shareableType == type && $0.shareableID == id }
    }

    /// The ids of everything shared at `org` scope in an organization, as of now
    /// — i.e. that org's shared library for a given type.
    func orgLibraryIDs(ofType type: ShareableType, in organizationID: UUID, asOf now: Date = Date()) -> [UUID] {
        shareGrants
            .filter { $0.shareableType == type && $0.organizationID == organizationID
                && $0.scope == .org && $0.isActive(asOf: now) }
            .map(\.shareableID)
    }
}

import Foundation

/// Organization / role reads, the permission bridge, and the solo-coach owner
/// bootstrap. Everything is scoped to an org via `OrgMembership`, so the same
/// schema serves "solo coach" and "50-team club" — the coach just holds
/// admin+director+coach in their personal org.
extension AppStore {

    // MARK: - Reads

    /// The always-present personal organization.
    var personalOrg: Organization {
        organizations.first { $0.id == Organization.personalID } ?? .personal
    }

    func organization(id: UUID) -> Organization? { organizations.first { $0.id == id } }

    /// The org that owns a team.
    func organization(for team: Team) -> Organization? { organization(id: team.organizationID) }

    /// The roles a person holds in an org (empty if they're not a member).
    func roles(ofPerson personID: UUID, in organizationID: UUID) -> Set<OrgRole> {
        orgMemberships.first { $0.personID == personID && $0.organizationID == organizationID }?.roles ?? []
    }

    /// Whether a person may perform a capability in an org (coarse role check;
    /// per-record scope — own team / own child / self — is enforced at fetch).
    func can(_ capability: Capability, person personID: UUID, in organizationID: UUID) -> Bool {
        Permissions.can(capability, asAnyOf: roles(ofPerson: personID, in: organizationID))
    }

    // MARK: - Owner bootstrap

    /// Ensures the signed-in coach exists as the owner of their personal org:
    /// a `Person`, a `UserAccount` linked to it, and an `OrgMembership` granting
    /// admin+director+coach. Idempotent, so it's safe to call on every sign-in.
    func ensureOwner(appleUserID: String, displayName: String?) {
        batch {
            if !organizations.contains(where: { $0.id == Organization.personalID }) {
                organizations.append(.personal)
            }

            let trimmedName = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
            let accountIndex = userAccounts.firstIndex { $0.appleUserID == appleUserID }
            // Deterministic coach id derived from the Apple user id, so the local
            // owner Person matches the backend's account Person (and syncs as one
            // identity). Falls back to any id already linked to the account.
            let ownerPersonID = accountIndex.flatMap { userAccounts[$0].personID }
                ?? Person.coachID(forAppleUserID: appleUserID)

            // Owner Person.
            if let personIndex = people.firstIndex(where: { $0.id == ownerPersonID }) {
                if let name = trimmedName, !name.isEmpty { people[personIndex].name = name }
            } else {
                people.append(Person(id: ownerPersonID, name: (trimmedName?.isEmpty == false) ? trimmedName! : "Coach"))
            }

            // Account linked to that Person.
            if let index = accountIndex {
                userAccounts[index].personID = ownerPersonID
                if let name = trimmedName, !name.isEmpty { userAccounts[index].displayName = name }
            } else {
                userAccounts.append(UserAccount(personID: ownerPersonID, appleUserID: appleUserID, displayName: trimmedName))
            }

            // Owner membership: admin + director + coach in the personal org.
            if !orgMemberships.contains(where: { $0.personID == ownerPersonID && $0.organizationID == Organization.personalID }) {
                orgMemberships.append(OrgMembership(
                    personID: ownerPersonID,
                    organizationID: Organization.personalID,
                    roles: [.admin, .director, .coach]
                ))
            }
        }
    }
}

import Foundation

/// Person/UserAccount reads and the sync that keeps a canonical `Person` in step
/// with each `Player`. Players still carry their identity fields (so no view has
/// to change yet), but the store mirrors them onto the `Person` on every add and
/// update — so the human's identity, contact, and medical details already live
/// independently, ready for the parent/player tiers and cross-season history.
extension AppStore {

    // MARK: - Reads

    func person(id: UUID) -> Person? { people.first { $0.id == id } }

    /// The human backing a player.
    func person(for player: Player) -> Person? { person(id: player.personID) }

    func userAccount(appleUserID: String) -> UserAccount? {
        userAccounts.first { $0.appleUserID == appleUserID }
    }

    // MARK: - Person sync

    /// Upserts the `Person` backing a player from that player's current identity,
    /// contact, and medical fields. Called by add/update so the two never drift.
    func syncPerson(from player: Player) {
        let person = Person(
            id: player.personID,
            name: player.name,
            guardian: player.guardian,
            guardianPhone: player.guardianPhone,
            guardianEmail: player.guardianEmail,
            secondaryContactName: player.secondaryContactName,
            secondaryContactPhone: player.secondaryContactPhone,
            emergencyContactName: player.emergencyContactName,
            emergencyContactPhone: player.emergencyContactPhone,
            emergencyContactRelation: player.emergencyContactRelation,
            allergies: player.allergies,
            medicalNotes: player.medicalNotes
        )
        if let index = people.firstIndex(where: { $0.id == person.id }) {
            people[index] = person
        } else {
            people.append(person)
        }
    }

    /// Removes the `Person` for a player id, unless another player still points at
    /// the same `Person` (they never do today, but the guard keeps a shared
    /// identity safe once guardianships arrive).
    func removePersonIfOrphaned(personID: UUID, excludingPlayer playerID: UUID) {
        let stillReferenced = players.contains { $0.id != playerID && $0.personID == personID }
        if !stillReferenced { people.removeAll { $0.id == personID } }
    }

    // MARK: - Accounts

    /// Records a signed-in Apple identity as a `UserAccount` (idempotent by Apple
    /// user id). The account isn't linked to a `Person` yet — that comes with the
    /// coach/org tier — matching the doc's nullable-owner design.
    func linkUserAccount(appleUserID: String, displayName: String?) {
        if let index = userAccounts.firstIndex(where: { $0.appleUserID == appleUserID }) {
            if let displayName, !displayName.isEmpty { userAccounts[index].displayName = displayName }
        } else {
            userAccounts.append(UserAccount(appleUserID: appleUserID, displayName: displayName))
        }
    }
}

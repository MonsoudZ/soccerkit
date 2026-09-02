import Foundation

@MainActor
final class PlayerFormViewModel: ObservableObject {
    let player: Player?
    @Published var name: String
    @Published var number: Int
    @Published var position: PlayerPosition
    @Published var guardian: String
    @Published var notes: String
    @Published var guardianPhone: String
    @Published var guardianEmail: String
    @Published var secondaryContactName: String
    @Published var secondaryContactPhone: String
    @Published var emergencyContactName: String
    @Published var emergencyContactPhone: String
    @Published var emergencyContactRelation: String
    @Published var allergies: String
    @Published var medicalNotes: String
    @Published var overrideMinMinutes: Bool
    @Published var minMinutes: Int

    init(player: Player?) {
        self.player = player
        name = player?.name ?? ""
        number = player?.number ?? 1
        position = player?.position ?? .midfielder
        guardian = player?.guardian ?? ""
        notes = player?.notes ?? ""
        guardianPhone = player?.guardianPhone ?? ""
        guardianEmail = player?.guardianEmail ?? ""
        secondaryContactName = player?.secondaryContactName ?? ""
        secondaryContactPhone = player?.secondaryContactPhone ?? ""
        emergencyContactName = player?.emergencyContactName ?? ""
        emergencyContactPhone = player?.emergencyContactPhone ?? ""
        emergencyContactRelation = player?.emergencyContactRelation ?? ""
        allergies = player?.allergies ?? ""
        medicalNotes = player?.medicalNotes ?? ""
        overrideMinMinutes = player?.minMinutesOverride != nil
        minMinutes = player?.minMinutesOverride ?? 0
    }

    var isEditing: Bool { player != nil }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Another player on the team already wears this number.
    func hasDuplicateNumber(in store: AppStore) -> Bool {
        store.roster.contains { $0.number == number && $0.id != player?.id }
    }

    func canSave(in store: AppStore) -> Bool {
        isValid && !hasDuplicateNumber(in: store)
    }

    /// Writes the form's fields onto a player. Editing starts from the stored
    /// player rather than building a fresh one, so everything this form doesn't
    /// ask about survives the save.
    ///
    /// Rebuilding from the form alone dropped two fields that aren't in its
    /// argument list: `developmentLog` defaulted to empty, so fixing a guardian's
    /// phone number erased a season of dated notes and skill ratings — and the
    /// deletion synced — and `personID` was re-derived from the player's id,
    /// which is harmless only while the two are equal. Both paths now go through
    /// `apply(to:)`, so a field added to this form can't be written on create and
    /// forgotten on edit.
    func save(into store: AppStore) {
        if let player {
            var updated = player
            apply(to: &updated)
            store.updatePlayer(updated)
        } else {
            // A blank slate to write onto: a new player has no development log,
            // and `Player.init` derives their `personID` from their own id.
            var created = Player(id: UUID(), name: "", number: number,
                                 position: position, guardian: "", notes: "")
            apply(to: &created)
            // A new player joins the currently selected team; edits leave the
            // existing membership untouched.
            store.addPlayer(created, toTeam: store.selectedTeamID)
        }
    }

    /// Every field this form owns, and nothing else.
    private func apply(to player: inout Player) {
        player.name = trimmed(name)
        player.number = number
        player.position = position
        player.guardian = trimmed(guardian)
        player.notes = notes
        player.guardianPhone = trimmed(guardianPhone)
        player.guardianEmail = trimmed(guardianEmail)
        player.secondaryContactName = trimmed(secondaryContactName)
        player.secondaryContactPhone = trimmed(secondaryContactPhone)
        player.emergencyContactName = trimmed(emergencyContactName)
        player.emergencyContactPhone = trimmed(emergencyContactPhone)
        player.emergencyContactRelation = trimmed(emergencyContactRelation)
        player.allergies = trimmed(allergies)
        player.medicalNotes = trimmed(medicalNotes)
        player.minMinutesOverride = overrideMinMinutes ? max(0, minMinutes) : nil
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

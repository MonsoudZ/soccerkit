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

    func save(into store: AppStore) {
        let updated = Player(
            id: player?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            number: number,
            position: position,
            guardian: guardian.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            guardianPhone: trimmed(guardianPhone),
            guardianEmail: trimmed(guardianEmail),
            secondaryContactName: trimmed(secondaryContactName),
            secondaryContactPhone: trimmed(secondaryContactPhone),
            emergencyContactName: trimmed(emergencyContactName),
            emergencyContactPhone: trimmed(emergencyContactPhone),
            emergencyContactRelation: trimmed(emergencyContactRelation),
            allergies: trimmed(allergies),
            medicalNotes: medicalNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            minMinutesOverride: overrideMinMinutes ? max(0, minMinutes) : nil
        )

        if player == nil {
            // A new player joins the currently selected team; edits leave the
            // existing membership untouched.
            store.addPlayer(updated, toTeam: store.selectedTeamID)
        } else {
            store.updatePlayer(updated)
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

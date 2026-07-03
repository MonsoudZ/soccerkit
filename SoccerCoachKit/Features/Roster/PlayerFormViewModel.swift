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
    }

    var isEditing: Bool { player != nil }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(into store: AppStore) {
        let updated = Player(
            id: player?.id ?? UUID(),
            teamID: player?.teamID ?? store.selectedTeamID,
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
            medicalNotes: medicalNotes.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if player == nil {
            store.players.append(updated)
        } else {
            store.updatePlayer(updated)
        }
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

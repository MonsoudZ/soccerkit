import Foundation
import SwiftUI

@MainActor
final class DevelopmentEntryFormViewModel: ObservableObject {
    let playerID: UUID
    let entry: DevelopmentEntry?
    @Published var date: Date
    @Published var notes: String
    @Published var ratings: [String: Int]

    init(playerID: UUID, entry: DevelopmentEntry?) {
        self.playerID = playerID
        self.entry = entry
        date = entry?.date ?? Date()
        notes = entry?.notes ?? ""
        ratings = entry?.ratings ?? [:]
    }

    var isEditing: Bool { entry != nil }

    func ratingBinding(for skill: SkillCategory) -> Binding<Int> {
        Binding(
            get: { self.ratings[skill.rawValue] ?? 0 },
            set: { self.ratings[skill.rawValue] = $0 }
        )
    }

    func save(into store: AppStore) {
        guard let player = store.players.first(where: { $0.id == playerID }) else { return }
        let saved = DevelopmentEntry(
            id: entry?.id ?? UUID(),
            date: date,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            ratings: ratings.filter { $0.value > 0 } // drop cleared ratings
        )
        store.saveDevelopmentEntry(saved, for: player)
    }
}

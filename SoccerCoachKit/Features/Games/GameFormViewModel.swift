import Foundation

@MainActor
final class GameFormViewModel: ObservableObject {
    let game: GameEvent?
    @Published var opponent: String
    @Published var date: Date
    @Published var location: String
    @Published var isHome: Bool
    @Published var notes: String

    init(game: GameEvent?, initialDate: Date?) {
        self.game = game
        opponent = game?.opponent ?? ""
        date = game?.date ?? initialDate ?? Date()
        location = game?.location ?? ""
        isHome = game?.isHome ?? true
        notes = game?.notes ?? ""
    }

    var isEditing: Bool { game != nil }

    var isValid: Bool {
        !opponent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func save(into store: AppStore) {
        let cleanOpponent = opponent.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if let game {
            var updated = game
            updated.opponent = cleanOpponent
            updated.date = date
            updated.location = cleanLocation
            updated.isHome = isHome
            updated.notes = cleanNotes
            store.updateGame(updated)
        } else {
            store.addGame(
                opponent: cleanOpponent,
                date: date,
                location: cleanLocation,
                isHome: isHome,
                notes: cleanNotes
            )
        }
    }
}

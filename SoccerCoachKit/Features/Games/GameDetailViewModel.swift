import Foundation

@MainActor
final class GameDetailViewModel: ObservableObject {
    let gameID: UUID
    @Published var showingEditGame = false
    @Published var showingReport = false

    init(gameID: UUID) {
        self.gameID = gameID
    }

    func game(in store: AppStore) -> GameEvent? {
        store.games.first { $0.id == gameID }
    }

    func delete(_ game: GameEvent, from store: AppStore) {
        store.deleteGame(game)
    }
}

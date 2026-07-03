import Foundation

@MainActor
final class GamesViewModel: ObservableObject {
    @Published var showingNewGame = false

    func delete(_ game: GameEvent, from store: AppStore) {
        store.deleteGame(game)
    }
}

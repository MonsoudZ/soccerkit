import Foundation

@MainActor
final class GamesViewModel: ObservableObject {
    @Published var showingNewGame = false
    @Published var searchText = ""

    var isSearching: Bool { SearchQuery.isActive(searchText) }

    /// The team's fixtures narrowed by the search text.
    func filteredGames(in store: AppStore) -> [GameEvent] {
        store.teamGames.filter {
            SearchQuery.matches(searchText, in: [$0.opponent, $0.location, $0.notes])
        }
    }

    func delete(_ game: GameEvent, from store: AppStore) {
        store.deleteGame(game)
    }
}

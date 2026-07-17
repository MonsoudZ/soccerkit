import Foundation

@MainActor
final class PlayerDetailViewModel: ObservableObject {
    let playerID: UUID
    @Published var showingEditPlayer = false
    @Published var showingNewEntry = false
    @Published var editingEntry: DevelopmentEntry?

    init(playerID: UUID) {
        self.playerID = playerID
    }

    func player(in store: AppStore) -> Player? {
        store.players.first { $0.id == playerID }
    }

    func delete(_ player: Player, from store: AppStore) {
        store.deletePlayer(player)
    }
}

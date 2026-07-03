import Foundation

@MainActor
final class RosterViewModel: ObservableObject {
    @Published var showingAddPlayer = false

    func delete(_ player: Player, from store: AppStore) {
        store.deletePlayer(player)
    }
}

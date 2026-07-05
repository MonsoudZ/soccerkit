import SwiftUI

struct GamesView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = GamesViewModel()

    var body: some View {
        List {
            if store.teamGames.isEmpty {
                Text("No games scheduled yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.teamGames) { game in
                    NavigationLink {
                        GameDetailView(gameID: game.id)
                    } label: {
                        GameSummaryCard(game: game)
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.delete(game, from: store)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .themedList()
        .toolbar {
            Button {
                viewModel.showingNewGame = true
            } label: {
                Label("New Game", systemImage: "plus")
            }
        }
        .sheet(isPresented: $viewModel.showingNewGame) {
            NavigationStack {
                GameFormView()
            }
        }
    }
}

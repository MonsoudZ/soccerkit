import SwiftUI

struct GameDetailView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: GameDetailViewModel

    init(gameID: UUID) {
        _viewModel = StateObject(wrappedValue: GameDetailViewModel(gameID: gameID))
    }

    var body: some View {
        Group {
            if let game = viewModel.game(in: store) {
                List {
                    Section("Game") {
                        LabeledContent("Opponent", value: game.opponent)
                        LabeledContent("Venue", value: game.isHome ? "Home" : "Away")
                        LabeledContent("Date", value: game.date.formatted(date: .abbreviated, time: .omitted))
                        LabeledContent("Time", value: game.date.formatted(date: .omitted, time: .shortened))
                        if !game.location.isEmpty {
                            LabeledContent("Location", value: game.location)
                        }
                    }

                    if !game.notes.isEmpty {
                        Section("Notes") {
                            Text(game.notes)
                        }
                    }

                    Section {
                        ForEach(store.roster) { player in
                            RSVPRow(player: player, status: game.rsvps[player.id] ?? .noResponse) { status in
                                store.setRSVP(status, for: player, in: game)
                            }
                        }
                    } header: {
                        Text("RSVP")
                    } footer: {
                        let summary = store.rsvpSummary(game.rsvps)
                        Text("\(summary.going) going · \(summary.maybe) maybe · \(summary.notGoing) not going · \(summary.total - summary.going - summary.maybe - summary.notGoing) no response")
                    }
                }
            } else {
                EmptyStateView(title: "Game Removed", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle(viewModel.game(in: store).map { "vs \($0.opponent)" } ?? "Game")
        .toolbar {
            if let game = viewModel.game(in: store) {
                Button {
                    viewModel.showingEditGame = true
                } label: {
                    Label("Edit Game", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    viewModel.delete(game, from: store)
                    dismiss()
                } label: {
                    Label("Delete Game", systemImage: "trash")
                }
            }
        }
        .sheet(isPresented: $viewModel.showingEditGame) {
            if let game = viewModel.game(in: store) {
                NavigationStack {
                    GameFormView(game: game)
                }
            }
        }
    }
}

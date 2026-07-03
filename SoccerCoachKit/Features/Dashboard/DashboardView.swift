import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var viewModel = DashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TeamHeader(team: store.selectedTeam)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                    MetricTile(title: "Players", value: "\(store.roster.count)", symbol: "person.3.fill")
                    MetricTile(title: "Sessions", value: "\(store.teamSessions.count)", symbol: "calendar")
                    MetricTile(title: "Games", value: "\(store.teamGames.count)", symbol: "soccerball")
                    MetricTile(title: "Drills", value: "\(store.teamDrills.count)", symbol: "sportscourt.fill")
                }

                if let game = store.nextGame {
                    SectionHeader("Next Game")
                    GameSummaryCard(game: game)
                }

                if let session = store.nextSession {
                    SectionHeader("Next Training")
                    SessionSummaryCard(session: session)
                }

                SectionHeader("Roster Snapshot")
                VStack(spacing: 10) {
                    ForEach(store.roster.prefix(5)) { player in
                        PlayerRow(player: player)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .toolbar {
            Menu {
                Button {
                    viewModel.showingEditTeam = true
                } label: {
                    Label("Edit Team", systemImage: "slider.horizontal.3")
                }

                Button {
                    viewModel.showingNewTeam = true
                } label: {
                    Label("New Team", systemImage: "plus")
                }

                if store.canDeleteTeam {
                    Divider()
                    Button(role: .destructive) {
                        viewModel.showingDeleteTeam = true
                    } label: {
                        Label("Delete Team", systemImage: "trash")
                    }
                }
            } label: {
                Label("Team Options", systemImage: "ellipsis.circle")
            }
        }
        .sheet(isPresented: $viewModel.showingNewTeam) {
            NavigationStack {
                TeamFormView()
            }
        }
        .sheet(isPresented: $viewModel.showingEditTeam) {
            NavigationStack {
                TeamFormView(team: store.selectedTeam)
            }
        }
        .confirmationDialog(
            "Delete \(store.selectedTeam.name)?",
            isPresented: $viewModel.showingDeleteTeam,
            titleVisibility: .visible
        ) {
            Button("Delete Team", role: .destructive) {
                store.deleteTeam(store.selectedTeam)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes the team and its players, games, sessions, events, and diagrams. Shared drills are kept.")
        }
    }
}

import SwiftUI

/// A single team's dashboard, drilled into from the coach home. Also makes this
/// the selected team so the other sidebar sections follow.
struct TeamDashboardView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let teamID: UUID

    @State private var showingEditTeam = false
    @State private var showingDeleteTeam = false

    var body: some View {
        Group {
            if let team = store.teams.first(where: { $0.id == teamID }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        TeamHeader(team: team)

                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
                            MetricTile(title: "Players", value: "\(store.players(inTeam: teamID).count)", symbol: "person.3.fill")
                            MetricTile(title: "Sessions", value: "\(store.sessions(inTeam: teamID).count)", symbol: "calendar")
                            MetricTile(title: "Games", value: "\(store.games(inTeam: teamID).count)", symbol: "soccerball")
                            MetricTile(title: "Drills", value: "\(store.drills(inTeam: teamID).count)", symbol: "sportscourt.fill")
                        }

                        if let game = store.nextGame(inTeam: teamID) {
                            SectionHeader("Next Game")
                            GameSummaryCard(game: game)
                        }

                        if let session = store.nextSession(inTeam: teamID) {
                            SectionHeader("Next Training")
                            SessionSummaryCard(session: session)
                        }

                        SectionHeader("Roster Snapshot")
                        VStack(spacing: 10) {
                            ForEach(store.players(inTeam: teamID).prefix(5)) { player in
                                PlayerRow(player: player)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
                .navigationTitle(team.name)
                .toolbar {
                    Menu {
                        Button {
                            showingEditTeam = true
                        } label: {
                            Label("Edit Team", systemImage: "slider.horizontal.3")
                        }
                        if store.canDeleteTeam {
                            Divider()
                            Button(role: .destructive) {
                                showingDeleteTeam = true
                            } label: {
                                Label("Delete Team", systemImage: "trash")
                            }
                        }
                    } label: {
                        Label("Team Options", systemImage: "ellipsis.circle")
                    }
                }
                .sheet(isPresented: $showingEditTeam) {
                    NavigationStack {
                        TeamFormView(team: team)
                    }
                }
                .confirmationDialog(
                    "Delete \(team.name)?",
                    isPresented: $showingDeleteTeam,
                    titleVisibility: .visible
                ) {
                    Button("Delete Team", role: .destructive) {
                        store.deleteTeam(team)
                        dismiss()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This permanently deletes the team and its players, games, sessions, events, and diagrams. Shared drills are kept.")
                }
            } else {
                EmptyStateView(title: "Team Removed", systemImage: "shield.slash")
            }
        }
        .onAppear {
            // Make this the active team so Roster, Games, etc. follow.
            if store.selectedTeamID != teamID, store.teams.contains(where: { $0.id == teamID }) {
                store.selectedTeamID = teamID
            }
        }
    }
}

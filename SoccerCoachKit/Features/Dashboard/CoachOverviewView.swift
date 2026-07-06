import SwiftUI

/// The coach's home: a cross-team overview that drills into a per-team
/// dashboard. Spans every team the coach manages rather than the selected one.
struct CoachOverviewView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showingNewTeam = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Spacing.lg)], spacing: Spacing.lg) {
                    MetricTile(title: store.teams.count == 1 ? "Team" : "Teams", value: "\(store.teams.count)", symbol: "shield.lefthalf.filled", accent: .brand)
                    MetricTile(title: "Players", value: "\(store.players.count)", symbol: "person.3.fill", accent: .info)
                    MetricTile(title: "Games", value: "\(store.games.count)", symbol: "soccerball", accent: .positive)
                    MetricTile(title: "Sessions", value: "\(store.sessions.count)", symbol: "calendar", accent: .caution)
                }

                if store.soonestGame != nil || store.soonestSession != nil {
                    SectionHeader("Up Next")
                    if let game = store.soonestGame {
                        upNext(team: store.teamName(for: game.teamID)) {
                            GameSummaryCard(game: game)
                        }
                    }
                    if let session = store.soonestSession {
                        upNext(team: store.teamName(for: session.teamID)) {
                            SessionSummaryCard(session: session)
                        }
                    }
                }

                SectionHeader("Teams")
                VStack(spacing: Spacing.lg) {
                    ForEach(store.teams) { team in
                        NavigationLink {
                            TeamDashboardView(teamID: team.id)
                        } label: {
                            TeamOverviewCard(
                                team: team,
                                playerCount: store.players(inTeam: team.id).count,
                                nextGame: store.nextGame(inTeam: team.id)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .screenBackground()
        .toolbar {
            Button {
                showingNewTeam = true
            } label: {
                Label("New Team", systemImage: "plus")
            }
        }
        .sheet(isPresented: $showingNewTeam) {
            NavigationStack {
                TeamFormView()
            }
        }
    }

    private func upNext<Content: View>(team: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(team)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }
}

private struct TeamOverviewCard: View {
    let team: Team
    let playerCount: Int
    let nextGame: GameEvent?

    var body: some View {
        HStack(spacing: Spacing.lg) {
            ZStack {
                Circle().fill(team.accentColor.opacity(0.2))
                Text(team.name.prefix(1))
                    .font(.headline.weight(.bold))
                    .foregroundStyle(team.accentColor)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(team.name)
                    .font(.headline)
                Text("\(team.ageGroup.rawValue) · \(team.season)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(playerCount) player\(playerCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let nextGame {
                    Label("vs \(nextGame.opponent) · \(nextGame.date.formatted(date: .abbreviated, time: .omitted))",
                          systemImage: "soccerball")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .surfaceStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(team.name), \(team.ageGroup.rawValue), \(playerCount) player\(playerCount == 1 ? "" : "s")")
        .accessibilityHint("Opens the team dashboard")
    }
}

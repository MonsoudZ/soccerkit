import SwiftUI

struct SeasonStatsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let games = store.teamGames
        let record = SeasonStats.teamRecord(games: games)
        let stats = SeasonStats.playerStats(players: store.roster, games: games)

        List {
            Section {
                LabeledContent("Season", value: store.selectedTeam.season)
                LabeledContent("Record (W-L-D)", value: record.summary)
                LabeledContent("Games Played", value: "\(record.played)")
                LabeledContent("Goals", value: "\(record.goalsFor) for · \(record.goalsAgainst) against")
                LabeledContent("Goal Difference", value: signed(record.goalDifference))
            } header: {
                Text("Record")
            } footer: {
                if record.played == 0 {
                    Text("Record a final score on a game to build the season record.")
                }
            }

            Section {
                if stats.isEmpty {
                    Text("No players on the roster yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(stats) { stat in
                        PlayerStatRow(stat: stat)
                    }
                }
            } header: {
                Text("Player Stats")
            } footer: {
                Text("Goals and assists come from post-game reports; games played counts games marked present or late.")
            }
        }
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

private struct PlayerStatRow: View {
    let stat: PlayerSeasonStats

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("#\(stat.player.number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Text(stat.player.name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if stat.contributions > 0 {
                    Text("\(stat.goals)G · \(stat.assists)A")
                        .font(.subheadline.weight(.semibold))
                }
            }

            HStack(spacing: 12) {
                Label("\(stat.gamesPlayed) GP", systemImage: "figure.soccer")
                if stat.averageEffort > 0 {
                    Label(String(format: "%.1f effort", stat.averageEffort), systemImage: "star.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.accessibilityLabel)
    }
}

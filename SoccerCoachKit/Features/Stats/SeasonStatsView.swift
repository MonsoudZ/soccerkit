import SwiftUI
import Charts

struct SeasonStatsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        let games = store.teamGames
        let record = SeasonStats.teamRecord(games: games)
        let stats = SeasonStats.playerStats(players: store.roster, games: games)
        let contributors = Array(stats.filter { $0.contributions > 0 }.prefix(6))

        List {
            Section {
                RecordBar(record: record)
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

            if !contributors.isEmpty {
                Section {
                    TopContributorsChart(contributors: contributors)
                        .padding(.vertical, Spacing.xs)
                } header: {
                    Text("Top Contributors")
                } footer: {
                    Text("Goals and assists per player, this season.")
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
        .themedList()
    }

    private func signed(_ value: Int) -> String {
        value > 0 ? "+\(value)" : "\(value)"
    }
}

/// A single proportional bar summarizing the season record — wins, draws, and
/// losses as coloured segments — for an at-a-glance read above the numbers.
private struct RecordBar: View {
    let record: TeamRecord

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    segment(record.wins, color: .positive, width: geo.size.width)
                    segment(record.draws, color: .caution, width: geo.size.width)
                    segment(record.losses, color: .critical, width: geo.size.width)
                }
            }
            .frame(height: 12)
            .clipShape(Capsule())

            HStack(spacing: Spacing.lg) {
                legend(count: record.wins, label: "W", color: .positive)
                legend(count: record.draws, label: "D", color: .caution)
                legend(count: record.losses, label: "L", color: .critical)
            }
            .font(.caption)
        }
        .padding(.vertical, Spacing.xs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Record: \(record.wins) wins, \(record.draws) draws, \(record.losses) losses")
    }

    @ViewBuilder
    private func segment(_ count: Int, color: Color, width: CGFloat) -> some View {
        let total = max(record.played, 1)
        if count > 0 {
            color.frame(width: max(4, width * CGFloat(count) / CGFloat(total)))
        }
    }

    private func legend(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: Spacing.xs) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count) \(label)").foregroundStyle(.secondary)
        }
    }
}

/// A stacked horizontal bar chart of each player's goals and assists.
private struct TopContributorsChart: View {
    let contributors: [PlayerSeasonStats]

    private enum Kind: String { case goals = "Goals", assists = "Assists" }

    var body: some View {
        Chart {
            ForEach(contributors) { stat in
                bar(stat.player.name, stat.goals, .goals, color: .brand)
                bar(stat.player.name, stat.assists, .assists, color: .info)
            }
        }
        .chartForegroundStyleScale([Kind.goals.rawValue: Color.brand, Kind.assists.rawValue: Color.info])
        .chartLegend(position: .top, alignment: .leading, spacing: Spacing.md)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine()
                AxisValueLabel()
            }
        }
        .frame(height: CGFloat(contributors.count) * 34 + 24)
    }

    private func bar(_ name: String, _ value: Int, _ kind: Kind, color: Color) -> some ChartContent {
        BarMark(
            x: .value("Count", value),
            y: .value("Player", name)
        )
        .foregroundStyle(by: .value("Type", kind.rawValue))
        .cornerRadius(3)
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

            HStack(spacing: Spacing.lg) {
                Label("\(stat.gamesPlayed) GP", systemImage: "figure.soccer")
                if stat.averageEffort > 0 {
                    Label(String(format: "%.1f effort", stat.averageEffort), systemImage: "star.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(stat.accessibilityLabel)
    }
}

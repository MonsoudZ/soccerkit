import SwiftUI

extension AvailabilityLevel {
    var color: Color {
        switch self {
        case .flagged: return .caution
        case .out: return .critical
        case .noResponse: return .secondary
        case .maybe: return .caution
        case .available: return .positive
        }
    }

    var symbol: String {
        switch self {
        case .flagged: return "exclamationmark.triangle.fill"
        case .out: return "xmark.circle.fill"
        case .noResponse: return "questionmark.circle"
        case .maybe: return "questionmark.circle.fill"
        case .available: return "checkmark.circle.fill"
        }
    }
}

/// A pre-game triage of the squad: who's available, who's flagged (injury or low
/// readiness), who's out, and who hasn't replied — worst-first.
struct SquadAvailabilityView: View {
    @EnvironmentObject private var store: AppStore
    let gameID: UUID

    private static let order: [AvailabilityLevel] = [.flagged, .out, .noResponse, .maybe, .available]

    var body: some View {
        Group {
            if let game = store.games.first(where: { $0.id == gameID }) {
                let board = SquadAvailability.board(
                    players: store.players(inTeam: game.teamID),
                    game: game,
                    history: store.games(inTeam: game.teamID)
                )
                let summary = SquadAvailability.summary(board)

                List {
                    Section {
                        SummaryStrip(summary: summary)
                    } footer: {
                        Text("Pulls together RSVP, pre-match readiness, and recent injury flags. Record check-ins on the game to sharpen this.")
                    }

                    ForEach(Self.order, id: \.self) { level in
                        let group = board.filter { $0.level == level }
                        if !group.isEmpty {
                            Section {
                                ForEach(group) { AvailabilityRow(entry: $0) }
                            } header: {
                                Label("\(level.label) (\(group.count))", systemImage: level.symbol)
                                    .foregroundStyle(level.color)
                            }
                        }
                    }
                }
                .themedList()
                .navigationTitle("Squad Availability")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                EmptyStateView(title: "Game Removed", systemImage: "calendar.badge.exclamationmark")
            }
        }
    }
}

private struct SummaryStrip: View {
    let summary: AvailabilitySummary

    var body: some View {
        HStack(spacing: Spacing.md) {
            pill(summary.available, "Available", .positive)
            pill(summary.maybe, "Maybe", .caution)
            pill(summary.flagged, "Flagged", .caution)
            pill(summary.out, "Out", .critical)
            pill(summary.noResponse, "No reply", .secondary)
        }
        .padding(.vertical, Spacing.xs)
    }

    @ViewBuilder
    private func pill(_ count: Int, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(count > 0 ? color : .secondary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AvailabilityRow: View {
    let entry: PlayerAvailability

    var body: some View {
        HStack(spacing: Spacing.md) {
            PlayerAvatar(number: entry.player.number, position: entry.player.position)

            VStack(alignment: .leading, spacing: Spacing.xxs) {
                Text(entry.player.name)
                    .font(.subheadline.weight(.semibold))
                Text("RSVP: \(entry.rsvp.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(entry.flags, id: \.self) { flag in
                    Label(flag, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundStyle(Color.caution)
                }
            }

            Spacer()

            Image(systemName: entry.level.symbol)
                .foregroundStyle(entry.level.color)
                .font(.headline)
        }
        .padding(.vertical, Spacing.xxs)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(entry.player.name), \(entry.level.label)\(entry.flags.isEmpty ? "" : ", " + entry.flags.joined(separator: ", "))")
    }
}

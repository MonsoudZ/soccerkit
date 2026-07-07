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
                        NavigationLink {
                            MatchQuestionnaireView(game: game, phase: .pre)
                        } label: {
                            Label {
                                summaryLabel("Pre-Match Check-In", filled: preMatchFilled(game))
                            } icon: {
                                IconChip(symbol: "checklist", accent: .info, size: 28)
                            }
                        }
                        NavigationLink {
                            MatchQuestionnaireView(game: game, phase: .post)
                        } label: {
                            Label {
                                summaryLabel("Post-Match Reflection", filled: postMatchFilled(game))
                            } icon: {
                                IconChip(symbol: "text.bubble", accent: .brand, size: 28)
                            }
                        }
                    } header: {
                        Text("Questionnaires")
                    } footer: {
                        Text("Player readiness and reflections, plus your game plan and review. Patterns show up on each player's profile.")
                    }

                    let gamePlans = store.diagrams(forGameID: game.id)
                    if !gamePlans.isEmpty {
                        Section {
                            ForEach(gamePlans) { diagram in
                                NavigationLink {
                                    DiagramPreviewView(diagramID: diagram.id)
                                } label: {
                                    Label {
                                        VStack(alignment: .leading, spacing: Spacing.xxs) {
                                            Text(diagram.title)
                                                .font(.headline)
                                            Text("Updated \(diagram.updatedAt, style: .date)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    } icon: {
                                        IconChip(symbol: "sportscourt.fill", accent: .info, size: 28)
                                    }
                                }
                            }
                        } header: {
                            Text("Game Plan")
                        } footer: {
                            Text("Diagrams attached to this game from the Field board.")
                        }
                    }

                    Section {
                        if let team = game.teamScore, let opponent = game.opponentScore {
                            LabeledContent("Result") {
                                Text("\(team) – \(opponent)\(game.resultLabel.map { " · \($0)" } ?? "")")
                                    .fontWeight(.semibold)
                            }
                        }

                        let reported = store.roster.filter { !(game.playerReports[$0.id]?.isEmpty ?? true) }
                        ForEach(reported) { player in
                            if let report = game.playerReports[player.id] {
                                PlayerReportRow(name: "#\(player.number)  \(player.name)", report: report)
                            }
                        }

                        Button {
                            viewModel.showingReport = true
                        } label: {
                            Label(game.teamScore == nil && game.playerReports.isEmpty ? "Add Post-Game Report" : "Edit Post-Game Report", systemImage: "square.and.pencil")
                        }
                    } header: {
                        Text("Post-Game")
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

                    Section {
                        ForEach(store.roster) { player in
                            AttendanceRow(player: player, status: game.attendance[player.id] ?? .absent) { status in
                                store.setAttendance(status, for: player, in: game)
                            }
                        }
                    } header: {
                        Text("Attendance")
                    } footer: {
                        let summary = store.attendanceSummary(for: game)
                        Text("\(summary.present) of \(summary.total) present")
                    }
                }
                .themedList()
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
        .sheet(isPresented: $viewModel.showingReport) {
            if let game = viewModel.game(in: store) {
                NavigationStack {
                    GameReportView(game: game)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryLabel(_ title: String, filled: Int) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            Text(title)
            Text(filled == 0 ? "Not started" : "\(filled) recorded")
                .font(.caption)
                .foregroundStyle(filled == 0 ? .secondary : Color.positive)
        }
    }

    /// How many players have a pre-match check-in, plus the coach plan (0/1).
    private func preMatchFilled(_ game: GameEvent) -> Int {
        game.preMatchCheckIns.values.filter { !$0.isEmpty }.count + (game.coachPreMatch.isEmpty ? 0 : 1)
    }

    private func postMatchFilled(_ game: GameEvent) -> Int {
        game.postMatchReflections.values.filter { !$0.isEmpty }.count + (game.coachPostMatch.isEmpty ? 0 : 1)
    }
}

/// Compact read-only summary of a single player's post-game report.
struct PlayerReportRow: View {
    let name: String
    let report: GamePlayerReport

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if !statLine.isEmpty {
                    Text(statLine)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            if report.effort > 0 {
                Text(String(repeating: "★", count: report.effort) + String(repeating: "☆", count: 5 - report.effort))
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }

            if !report.developmentFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(report.developmentFocus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statLine: String {
        var parts: [String] = []
        if report.goals > 0 { parts.append("\(report.goals)G") }
        if report.assists > 0 { parts.append("\(report.assists)A") }
        return parts.joined(separator: " · ")
    }
}

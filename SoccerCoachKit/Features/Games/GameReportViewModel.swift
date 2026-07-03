import Foundation
import SwiftUI

/// Edits a working copy of a game's post-game report (result + per-player
/// records) and writes it back to the store on save.
@MainActor
final class GameReportViewModel: ObservableObject {
    let gameID: UUID
    @Published var recordScore: Bool
    @Published var teamScore: Int
    @Published var opponentScore: Int
    @Published var reports: [UUID: GamePlayerReport]

    init(game: GameEvent) {
        gameID = game.id
        recordScore = game.teamScore != nil || game.opponentScore != nil
        teamScore = game.teamScore ?? 0
        opponentScore = game.opponentScore ?? 0
        reports = game.playerReports
    }

    // MARK: - Per-field bindings

    func binding<Value>(_ keyPath: WritableKeyPath<GamePlayerReport, Value>, for playerID: UUID) -> Binding<Value> {
        Binding(
            get: { self.reports[playerID, default: GamePlayerReport()][keyPath: keyPath] },
            set: { newValue in
                var report = self.reports[playerID] ?? GamePlayerReport()
                report[keyPath: keyPath] = newValue
                self.reports[playerID] = report
            }
        )
    }

    // MARK: - Save

    func save(into store: AppStore) {
        guard var game = store.games.first(where: { $0.id == gameID }) else { return }
        game.teamScore = recordScore ? teamScore : nil
        game.opponentScore = recordScore ? opponentScore : nil
        // Drop blank reports so they don't clutter storage.
        game.playerReports = reports.filter { !$0.value.isEmpty }
        store.updateGame(game)
    }
}

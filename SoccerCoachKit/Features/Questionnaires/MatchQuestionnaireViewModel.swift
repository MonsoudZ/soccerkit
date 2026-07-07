import Foundation
import SwiftUI

/// Edits working copies of a game's pre/post-match questionnaires (per-player
/// check-ins/reflections + the coach's plan/review) and writes them back on save.
@MainActor
final class MatchQuestionnaireViewModel: ObservableObject {
    let gameID: UUID
    @Published var preCheckIns: [UUID: PreMatchCheckIn]
    @Published var postReflections: [UUID: PostMatchReflection]
    @Published var coachPre: CoachPreMatchPlan
    @Published var coachPost: CoachPostMatchReview

    init(game: GameEvent) {
        gameID = game.id
        preCheckIns = game.preMatchCheckIns
        postReflections = game.postMatchReflections
        coachPre = game.coachPreMatch
        coachPost = game.coachPostMatch
    }

    func preBinding<Value>(_ keyPath: WritableKeyPath<PreMatchCheckIn, Value>, for playerID: UUID) -> Binding<Value> {
        Binding(
            get: { self.preCheckIns[playerID, default: PreMatchCheckIn()][keyPath: keyPath] },
            set: { self.preCheckIns[playerID, default: PreMatchCheckIn()][keyPath: keyPath] = $0 }
        )
    }

    func postBinding<Value>(_ keyPath: WritableKeyPath<PostMatchReflection, Value>, for playerID: UUID) -> Binding<Value> {
        Binding(
            get: { self.postReflections[playerID, default: PostMatchReflection()][keyPath: keyPath] },
            set: { self.postReflections[playerID, default: PostMatchReflection()][keyPath: keyPath] = $0 }
        )
    }

    /// A short "X/8 rated" style progress hint for a player's pre-match row.
    func preProgress(for playerID: UUID) -> String {
        let checkIn = preCheckIns[playerID] ?? PreMatchCheckIn()
        let rated = checkIn.scales.filter { $0.value > 0 }.count
        if let readiness = checkIn.readiness {
            return String(format: "Readiness %.1f · %d/8", readiness, rated)
        }
        return "Not started"
    }

    func postProgress(for playerID: UUID) -> String {
        let reflection = postReflections[playerID] ?? PostMatchReflection()
        let rated = reflection.scales.filter { $0.value > 0 }.count
        return rated == 0 ? "Not started" : "\(rated)/5 rated"
    }

    func save(into store: AppStore) {
        guard var game = store.games.first(where: { $0.id == gameID }) else { return }
        game.preMatchCheckIns = preCheckIns.filter { !$0.value.isEmpty }
        game.postMatchReflections = postReflections.filter { !$0.value.isEmpty }
        game.coachPreMatch = coachPre
        game.coachPostMatch = coachPost
        store.updateGame(game)
    }
}

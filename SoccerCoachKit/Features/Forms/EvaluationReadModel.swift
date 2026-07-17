import Foundation

/// A single point on a readiness/effort trend line.
struct TrendPoint: Identifiable {
    let id: Int
    let date: Date
    let value: Double
}

/// One player's readiness standing, for the squad board.
struct SquadReadinessEntry: Identifiable {
    let player: Player
    /// Mean pre-match readiness across everything recorded; `nil` = no check-ins.
    let averageReadiness: Double?
    /// How many pre-match check-ins fed the average.
    let sampleCount: Int

    var id: UUID { player.id }
}

/// The read side of the evaluation engine: it projects *every* source of
/// evaluation data about a subject into the engine's `FormInstance` shape and
/// aggregates it with `FormEngine`. This is the doc's payoff — "the readiness
/// mean, the effort trend … all become one query shape over FormAnswer."
///
/// The app writes built-in evaluations through the legacy game-day/development
/// flows; this projects those dictionaries into the `FormInstance` shape on the
/// fly (via `FormMigration`, never persisted) so the trends read from one query.
/// Stored engine instances contribute only custom templates — the built-in
/// concepts come solely from the legacy source, so a concept is never counted
/// twice (see `athleteInstances`).
enum EvaluationReadModel {

    // MARK: - Projection

    /// Every evaluation about an athlete, from all sources, as instances.
    ///
    /// Built-in concepts (pre-match check-in, post-match reflection, game report,
    /// development) are written through the legacy game-day/development flows and
    /// projected below. A *stored* instance of a built-in template would be a
    /// second copy of that same concept — the double-count this once produced —
    /// so stored instances contribute only non-built-in (custom) templates; the
    /// legacy source is authoritative for the built-ins.
    static func athleteInstances(playerID: UUID, developmentLog: [DevelopmentEntry],
                                 games: [GameEvent], stored: [FormInstance]) -> [FormInstance] {
        let builtInIDs = Set(FormTemplateCatalog.builtIns.map(\.id))
        var result = stored.filter {
            $0.subject.type == .athlete && $0.subject.id == playerID
                && !builtInIDs.contains($0.templateID)
        }

        for game in games {
            if let checkIn = game.preMatchCheckIns[playerID], !checkIn.isEmpty {
                result.append(FormMigration.instance(from: checkIn, athlete: playerID, game: game.id, submittedAt: game.date))
            }
            if let reflection = game.postMatchReflections[playerID], !reflection.isEmpty {
                result.append(FormMigration.instance(from: reflection, athlete: playerID, game: game.id, submittedAt: game.date))
            }
            if let report = game.playerReports[playerID], !report.isEmpty {
                result.append(FormMigration.instance(from: report, athlete: playerID, game: game.id, submittedAt: game.date))
            }
        }

        for entry in developmentLog where !entry.isEmpty {
            result.append(FormMigration.instance(from: entry, athlete: playerID))
        }

        return result
    }

    // MARK: - Trends

    /// Pre-match readiness (the mean of each check-in's wellness scales) over
    /// time, oldest first.
    static func readinessTrend(_ instances: [FormInstance]) -> [TrendPoint] {
        composite(instances, template: FormTemplateCatalog.preMatchCheckIn)
    }

    /// Average pre-match readiness across all recorded check-ins.
    static func averageReadiness(_ instances: [FormInstance]) -> Double? {
        let values = readinessTrend(instances).map(\.value)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Coach-rated effort per game over time, oldest first.
    static func effortTrend(_ instances: [FormInstance]) -> [TrendPoint] {
        let reports = instances.filter { $0.templateID == FormTemplateCatalog.ID.playerGameReport }
        return FormEngine.series(ofField: "effort", across: reports)
            .enumerated()
            .map { index, point in TrendPoint(id: index, date: point.date, value: point.value) }
    }

    /// The composite (mean-of-scales) score per instance of one template, over time.
    private static func composite(_ instances: [FormInstance], template: FormTemplate) -> [TrendPoint] {
        instances
            .filter { $0.templateID == template.id }
            .sorted { $0.submittedAt < $1.submittedAt }
            .enumerated()
            .compactMap { index, instance in
                FormEngine.scaleMean(of: instance, using: template)
                    .map { TrendPoint(id: index, date: instance.submittedAt, value: $0) }
            }
    }

    // MARK: - Squad

    /// Every player's readiness standing, lowest first — so the coach sees who to
    /// check on. Players with no check-ins sort to the bottom.
    static func squadReadiness(players: [Player], games: [GameEvent], stored: [FormInstance]) -> [SquadReadinessEntry] {
        players
            .map { player -> SquadReadinessEntry in
                let instances = athleteInstances(playerID: player.id, developmentLog: player.developmentLog,
                                                 games: games, stored: stored)
                let trend = readinessTrend(instances)
                let average = trend.isEmpty ? nil : trend.map(\.value).reduce(0, +) / Double(trend.count)
                return SquadReadinessEntry(player: player, averageReadiness: average, sampleCount: trend.count)
            }
            .sorted { lhs, rhs in
                switch (lhs.averageReadiness, rhs.averageReadiness) {
                case let (l?, r?): return l != r ? l < r : lhs.player.name < rhs.player.name
                case (nil, _?): return false          // no data sinks below rated players
                case (_?, nil): return true
                case (nil, nil): return lhs.player.name < rhs.player.name
                }
            }
    }
}

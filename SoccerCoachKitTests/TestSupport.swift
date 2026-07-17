import Foundation
@testable import SoccerCoachKit

/// Persistence backed by memory (or primed to return a specific result) so tests
/// don't touch UserDefaults.
final class InMemoryPersistence: PersistenceService {
    private var storedByNamespace: [String: AppSnapshot] = [:]
    private var namespace = "" // "" == guest / signed-out
    private(set) var backedUp: Data?

    init(stored: AppSnapshot? = nil) { storedByNamespace[""] = stored }

    /// The snapshot for the current namespace (kept for existing tests).
    var stored: AppSnapshot? {
        get { storedByNamespace[namespace] }
        set { storedByNamespace[namespace] = newValue }
    }

    func load() -> PersistenceLoadResult { stored.map { .success($0) } ?? .empty }
    func save(_ snapshot: AppSnapshot) { stored = snapshot }
    func setNamespace(_ namespace: String?) { self.namespace = namespace ?? "" }
    func backupCorruptData(_ data: Data) { backedUp = data }
    func flushPendingSync() {}
    func corruptBackup() -> Data? { backedUp }
    func clearCorruptBackup() { backedUp = nil }
    func purge() {
        storedByNamespace[namespace] = nil
        backedUp = nil
    }
}

/// In-memory `TokenStorage` so token tests are isolated from the shared system
/// keychain (and from each other).
final class InMemoryTokenStorage: TokenStorage {
    private var values: [String: String] = [:]
    func string(forKey key: String) -> String? { values[key] }
    func set(_ value: String?, forKey key: String) { values[key] = value }
}

/// A controllable monotonic clock for `GameDayViewModel` tests.
final class TestClock {
    var seconds: TimeInterval = 0
    func now() -> TimeInterval { seconds }
    func advance(_ by: TimeInterval) { seconds += by }
}

enum TestData {
    static func team(
        id: UUID = UUID(),
        ageGroup: AgeGroup = .u6,
        periodFormat: PeriodFormat? = nil,
        minMinutes: Int? = nil
    ) -> Team {
        Team(id: id, name: "Test FC", ageGroup: ageGroup, season: "2026", accentName: "Teal",
             periodFormat: periodFormat, defaultMinimumMinutes: minMinutes)
    }

    static func player(teamID: UUID, number: Int, minOverride: Int? = nil) -> Player {
        Player(id: UUID(), teamID: teamID, name: "Player \(number)", number: number,
               position: .midfielder, guardian: "Guardian", notes: "", minMinutesOverride: minOverride)
    }

    static func drill(teamID: UUID?, title: String = "Drill") -> Drill {
        Drill(id: UUID(), teamID: teamID, title: title, category: .technical,
              durationMinutes: 15, fieldSetup: "Setup", coachingPoints: ["Point"])
    }

    static func snapshot(playerCount: Int = 6, ageGroup: AgeGroup = .u6) -> AppSnapshot {
        let t = team(ageGroup: ageGroup)
        let players = (1...playerCount).map { player(teamID: t.id, number: $0) }
        return AppSnapshot(teams: [t], players: players, drills: [], sessions: [],
                           diagrams: [], games: [], events: [], selectedTeamID: t.id)
    }

    @MainActor
    static func store(_ snapshot: AppSnapshot? = nil) -> AppStore {
        AppStore(snapshot: snapshot ?? Self.snapshot(), persistence: InMemoryPersistence())
    }
}

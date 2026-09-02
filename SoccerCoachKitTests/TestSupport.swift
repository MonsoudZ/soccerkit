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
    @discardableResult
    func set(_ value: String?, forKey key: String) -> Bool {
        values[key] = value
        return true
    }
}

/// `TokenStorage` that refuses every write, standing in for a keychain the app
/// can't write to (locked before first unlock, item inaccessible, entitlement
/// missing). The real `KeychainTokenStorage` can't be driven into that state
/// from a test host — `testKeychainRoundTrip` is skipped in CI for the same
/// reason — so this covers what actually matters: that a failed write is
/// reported and acted on rather than swallowed.
final class FailingTokenStorage: TokenStorage {
    /// What reads return. Seeded so a test can model the real shape of the
    /// failure — the keychain still holds the *old* session, it just won't take
    /// the new one — rather than an empty store, which short-circuits any caller
    /// that reads before it writes.
    private let seed: [String: String]
    private(set) var attemptedKeys: [String] = []

    init(seed: [String: String] = [:]) { self.seed = seed }

    func string(forKey key: String) -> String? { seed[key] }

    @discardableResult
    func set(_ value: String?, forKey key: String) -> Bool {
        attemptedKeys.append(key)
        return false // and the seed is left untouched: the write didn't land
    }
}

/// A stand-in Info.plist, so the backend-configuration rules can be tested for
/// what they are rather than against however the running bundle happens to be
/// built (a developer's gitignored `Config/Local.xcconfig` used to decide the
/// outcome).
struct StubInfoDictionary: InfoDictionary {
    private let values: [String: Any]
    init(_ values: [String: Any] = [:]) { self.values = values }
    func infoValue(forKey key: String) -> Any? { values[key] }

    /// No `BackendBaseURL` at all — a build that was never pointed at a server.
    static let unconfigured = StubInfoDictionary()
    /// What an unset `$(BACKEND_BASE_URL)` actually expands to in the plist.
    static let empty = StubInfoDictionary([BackendConfig.baseURLKey: ""])
}

/// In-memory `GameDaySessionStore`, so a relaunch can be simulated by handing
/// the same store to a second view model without touching the real defaults.
final class InMemoryGameDaySessionStore: GameDaySessionStore {
    private(set) var stored: GameDaySession?
    private(set) var clearCount = 0

    init(_ stored: GameDaySession? = nil) { self.stored = stored }

    func load() -> GameDaySession? { stored }
    func save(_ session: GameDaySession) { stored = session }
    func clear() { stored = nil; clearCount += 1 }
}

/// A controllable wall clock, for the restore rules (which are all about how
/// much real time passed while the app wasn't running).
final class TestDate {
    private(set) var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_700_000_000)) { current = start }
    func now() -> Date { current }
    func advance(_ by: TimeInterval) { current = current.addingTimeInterval(by) }
}

/// Real AES-GCM, but with the key held in memory instead of the Keychain.
///
/// For tests about persistence rather than encryption. The unsigned test host
/// has no usable Keychain — the same reason `testKeychainRoundTrip` is skipped
/// in CI — so a persistence service built with the production cipher can't seal
/// anything there and, correctly, writes nothing at all.
enum TestCipher {
    /// A cipher whose key survives for as long as `keyStore`, so two services
    /// sharing one can read each other's writes the way two launches would.
    static func inMemory(_ keyStore: InMemoryTokenStorage = InMemoryTokenStorage()) -> SnapshotCipher {
        KeychainSnapshotCipher(storage: keyStore)
    }
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

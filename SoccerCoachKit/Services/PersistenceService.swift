import Foundation

/// Outcome of attempting to load the persisted snapshot. Distinguishing "no
/// data yet" from "data present but undecodable" is what prevents a decode
/// failure from being silently replaced with — and then overwritten by —
/// fallback data.
enum PersistenceLoadResult {
    /// No snapshot has been stored yet (fresh install).
    case empty
    /// A snapshot was found and decoded successfully.
    case success(AppSnapshot)
    /// A snapshot was found but could not be decoded. The raw bytes are carried
    /// back so the caller can preserve them instead of overwriting them.
    case corrupt(data: Data, error: Error)
}

/// Abstraction over where the app's snapshot is stored. Keeping this behind a
/// protocol lets the store be initialized with an alternate backend (in-memory
/// for tests and previews, or a future file/CloudKit implementation) without
/// touching the view or store logic.
protocol PersistenceService {
    func load() -> PersistenceLoadResult
    func save(_ snapshot: AppSnapshot)
    /// Preserve an undecodable blob under a separate key so that a subsequent
    /// fallback save can't destroy the user's (recoverable) data.
    func backupCorruptData(_ data: Data)
}

/// Default persistence backed by `UserDefaults`, storing a JSON-encoded snapshot.
final class UserDefaultsPersistenceService: PersistenceService {
    private let defaults: UserDefaults
    private let storageKey: String
    private let backupKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "SoccerCoachKit.AppSnapshot.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
        self.backupKey = storageKey + ".corrupt-backup"
    }

    func load() -> PersistenceLoadResult {
        guard let data = defaults.data(forKey: storageKey) else {
            return .empty
        }

        do {
            let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: data)
            return .success(snapshot)
        } catch {
            // Surface the raw bytes rather than collapsing to `nil`: the caller
            // must be able to tell corruption apart from a fresh install so it
            // never overwrites recoverable data with sample content.
            return .corrupt(data: data, error: error)
        }
    }

    func save(_ snapshot: AppSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Encoding a value type we fully own should never fail; assert so a
            // regression is visible instead of silently dropping every write.
            assertionFailure("Failed to encode AppSnapshot: \(error)")
        }
    }

    func backupCorruptData(_ data: Data) {
        // Keep the first (closest-to-original) backup; don't clobber it if the
        // app relaunches before the user has recovered it.
        guard defaults.data(forKey: backupKey) == nil else { return }
        defaults.set(data, forKey: backupKey)
    }
}

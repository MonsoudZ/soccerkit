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
    /// Synchronously writes any pending snapshot. Called before the app
    /// suspends so an in-flight background write isn't lost on termination.
    func flushPendingSync()
    /// The most recent undecodable blob, if one was backed up, so it can be
    /// exported for recovery.
    func corruptBackup() -> Data?
    func clearCorruptBackup()
}

/// Default persistence backed by `UserDefaults`, storing a JSON-encoded
/// snapshot. Writes are encoded off the main thread and coalesced, so rapid
/// mutations don't block the UI or waste work.
final class UserDefaultsPersistenceService: PersistenceService {
    private let defaults: UserDefaults
    private let storageKey: String
    private let backupKey: String
    private let queue = DispatchQueue(label: "SoccerCoachKit.persistence", qos: .utility)
    private let lock = NSLock()
    private var pending: AppSnapshot?

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
        // Keep only the latest snapshot; one background pass writes it. If a
        // pass is already scheduled it will pick this up, so don't queue another.
        lock.lock()
        let alreadyScheduled = pending != nil
        pending = snapshot
        lock.unlock()

        guard !alreadyScheduled else { return }
        queue.async { [weak self] in self?.drain() }
    }

    func flushPendingSync() {
        // Block until the queue is idle and any pending snapshot is written.
        queue.sync { [weak self] in self?.drain() }
    }

    func backupCorruptData(_ data: Data) {
        // Keep the first (closest-to-original) backup; don't clobber it if the
        // app relaunches before the user has recovered it.
        guard defaults.data(forKey: backupKey) == nil else { return }
        defaults.set(data, forKey: backupKey)
    }

    func corruptBackup() -> Data? { defaults.data(forKey: backupKey) }

    func clearCorruptBackup() { defaults.removeObject(forKey: backupKey) }

    // MARK: - Background writing

    private func drain() {
        while let snapshot = takePending() {
            write(snapshot)
        }
    }

    private func takePending() -> AppSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = pending
        pending = nil
        return snapshot
    }

    private func write(_ snapshot: AppSnapshot) {
        do {
            let data = try JSONEncoder().encode(snapshot)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Encoding a value type we fully own should never fail; assert so a
            // regression is visible instead of silently dropping every write.
            assertionFailure("Failed to encode AppSnapshot: \(error)")
        }
    }
}

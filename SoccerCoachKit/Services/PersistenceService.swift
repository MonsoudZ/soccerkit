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
protocol PersistenceService: AnyObject {
    /// Reports whether each write reached disk, so the app can tell the coach
    /// when their changes aren't being saved instead of losing them quietly.
    /// Called on a background queue.
    var onWriteOutcome: ((_ saved: Bool) -> Void)? { get set }

    func load() -> PersistenceLoadResult
    func save(_ snapshot: AppSnapshot)
    /// Switches which user's data this store reads and writes. Passing a coach's
    /// Apple user id partitions their data so a different account on the same
    /// device can't see it; `nil` is the signed-out / guest namespace. Any
    /// pending write for the outgoing namespace is flushed first.
    func setNamespace(_ namespace: String?)
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
    /// Permanently removes the current namespace's stored snapshot and any
    /// corrupt backup — for account deletion. Drops any pending write first so it
    /// can't resurrect the data after the wipe.
    func purge()
}

/// Default persistence backed by `UserDefaults`, storing a JSON-encoded
/// snapshot — sealed, not in the clear, because the roster it holds carries
/// children's medical notes and their guardians' contact details (see
/// `SnapshotCipher`). Writes are encoded off the main thread and coalesced, so
/// rapid mutations don't block the UI or waste work.
final class UserDefaultsPersistenceService: PersistenceService {
    private let defaults: UserDefaults
    private let baseKey: String
    private var namespace: String?
    private var storageKey: String { namespace.map { "\(baseKey).\($0)" } ?? baseKey }
    private var backupKey: String { storageKey + ".corrupt-backup" }
    private let queue = DispatchQueue(label: "SoccerCoachKit.persistence", qos: .utility)
    private let lock = NSLock()
    private var pending: AppSnapshot?
    private let cipher: SnapshotCipher
    var onWriteOutcome: ((_ saved: Bool) -> Void)?

    init(defaults: UserDefaults = .standard,
         namespace: String? = nil,
         baseKey: String = "SoccerCoachKit.AppSnapshot.v1",
         cipher: SnapshotCipher = KeychainSnapshotCipher()) {
        self.defaults = defaults
        self.baseKey = baseKey
        self.namespace = namespace
        self.cipher = cipher
    }

    func setNamespace(_ namespace: String?) {
        flushPendingSync() // finish writing the outgoing user's data first
        self.namespace = namespace
    }

    func load() -> PersistenceLoadResult {
        guard let data = defaults.data(forKey: storageKey) else {
            return .empty
        }

        if let plaintext = try? cipher.open(data) {
            do {
                return .success(try JSONDecoder().decode(AppSnapshot.self, from: plaintext))
            } catch {
                return .corrupt(data: data, error: error)
            }
        }

        // Not sealed, or not sealed with a key we hold. Either it predates
        // encryption at rest, or it came from a device whose key didn't travel
        // with it (an unencrypted backup restored elsewhere).
        do {
            let snapshot = try JSONDecoder().decode(AppSnapshot.self, from: data)
            // Migrate on read. Waiting for the coach's next edit would work, but
            // until they make one their players' medical notes stay on disk in
            // the clear — and a coach who only ever reads the roster never makes
            // one.
            save(snapshot)
            return .success(snapshot)
        } catch {
            // Surface the raw bytes rather than collapsing to `nil`: the caller
            // must be able to tell corruption apart from a fresh install so it
            // never overwrites recoverable data with sample content. Ciphertext
            // we have no key for lands here too, and is preserved for the same
            // reason — it is unreadable, not worthless.
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

    /// The preserved blob, unsealed when we hold the key.
    ///
    /// This exists so a coach can export and inspect data the app couldn't read.
    /// The stored copy stays sealed — leaving decrypted medical notes parked
    /// under a backup key would undo the point — but a blob that failed to
    /// *decode* after decrypting fine is exactly the recoverable case, so it
    /// comes back out readable. One we have no key for comes back as it is:
    /// unreadable, and still the only copy.
    func corruptBackup() -> Data? {
        guard let stored = defaults.data(forKey: backupKey) else { return nil }
        return (try? cipher.open(stored)) ?? stored
    }

    func clearCorruptBackup() { defaults.removeObject(forKey: backupKey) }

    func purge() {
        // Drop any pending write so `drain()` can't re-persist the snapshot after
        // the keys are removed.
        lock.lock()
        pending = nil
        lock.unlock()
        defaults.removeObject(forKey: storageKey)
        defaults.removeObject(forKey: backupKey)
    }

    // MARK: - Background writing

    private func drain() {
        while let snapshot = takePending() {
            let saved = write(snapshot)
            onWriteOutcome?(saved)
            guard saved else {
                // Couldn't seal it. Hand it back rather than drop the coach's
                // changes on the floor, and stop: retrying in this loop would
                // spin on the same unavailable key.
                returnUnwritten(snapshot)
                return
            }
        }
    }

    private func takePending() -> AppSnapshot? {
        lock.lock()
        defer { lock.unlock() }
        let snapshot = pending
        pending = nil
        return snapshot
    }

    /// Puts an unwritten snapshot back so the next `save` or `flushPendingSync`
    /// tries again — unless a newer one arrived while we were failing, which
    /// supersedes it.
    private func returnUnwritten(_ snapshot: AppSnapshot) {
        lock.lock()
        defer { lock.unlock() }
        if pending == nil { pending = snapshot }
    }

    /// Writes the snapshot, sealed. Returns whether it landed.
    private func write(_ snapshot: AppSnapshot) -> Bool {
        let encoded: Data
        do {
            encoded = try JSONEncoder().encode(snapshot)
        } catch {
            // Encoding a value type we fully own should never fail; assert so a
            // regression is visible instead of silently dropping every write.
            // Unrecoverable, so it isn't handed back for a retry.
            assertionFailure("Failed to encode AppSnapshot: \(error)")
            return true
        }

        do {
            defaults.set(try cipher.seal(encoded), forKey: storageKey)
            return true
        } catch {
            // The Keychain wouldn't give up the key. That is a runtime condition
            // rather than a bug — a background launch before the device's first
            // unlock can hit it — so it must not trap.
            //
            // There is deliberately no plaintext fallback. Writing the clear JSON
            // is the one outcome worse than not writing it, because that is a
            // squad of children's medical notes on disk. The snapshot goes back
            // on the queue instead, and the next flush (the app is flushed on its
            // way to the background) writes it once the key is readable again.
            return false
        }
    }
}

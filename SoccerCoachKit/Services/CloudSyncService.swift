import Foundation

/// The subset of `NSUbiquitousKeyValueStore` the sync service needs, so it can
/// be faked in tests (the real store is a process-wide singleton).
protocol KeyValueSyncStore: AnyObject {
    func syncData(forKey key: String) -> Data?
    func setSyncData(_ data: Data?, forKey key: String)
    @discardableResult func synchronize() -> Bool
}

extension NSUbiquitousKeyValueStore: KeyValueSyncStore {
    func syncData(forKey key: String) -> Data? { data(forKey: key) }
    func setSyncData(_ data: Data?, forKey key: String) { set(data, forKey: key) }
}

/// Mirrors the app snapshot to iCloud key-value storage so a coach's data
/// follows them across devices. Local `UserDefaults` remains the fast, offline
/// source of truth; iCloud is a best-effort mirror (≤ 1 MB, last-writer-wins at
/// the document level). `onRemoteChange` fires when another device pushes a
/// newer snapshot.
@MainActor
final class CloudSyncService {
    static let key = "appSnapshot"
    /// KVS caps a single value near 1 MB; stay under it and skip oversize writes
    /// rather than letting the store silently reject them.
    private static let maxValueBytes = 900_000

    private let store: KeyValueSyncStore
    private var observer: NSObjectProtocol?
    /// The last bytes we wrote or read, to suppress our own echoes and no-op
    /// duplicate pulls.
    private var lastData: Data?

    /// Gates uploads until iCloud has reported its initial state. Prevents a
    /// fresh device (still showing sample data while the real snapshot downloads)
    /// from pushing that sample data up and clobbering good remote data.
    var hasSyncedInitialState = false

    var isEnabled: Bool
    var onRemoteChange: ((AppSnapshot) -> Void)?

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys] // stable bytes for echo detection
        return encoder
    }()

    init(store: KeyValueSyncStore = NSUbiquitousKeyValueStore.default, enabled: Bool) {
        self.store = store
        self.isEnabled = enabled
    }

    /// Begins observing external changes and pulls any newer remote snapshot.
    func start() {
        guard isEnabled, observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store as? NSUbiquitousKeyValueStore,
            queue: .main
        ) { [weak self] note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated { self?.handleExternalChange(reason: reason) }
        }
        store.synchronize()
        // If iCloud has already downloaded a value, it's safe to upload from now on.
        if store.syncData(forKey: Self.key) != nil { hasSyncedInitialState = true }
        pullRemote()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    private func handleExternalChange(reason: Int?) {
        switch reason {
        case NSUbiquitousKeyValueStoreAccountChange, NSUbiquitousKeyValueStoreQuotaViolationChange:
            // The iCloud account changed (sign-out / different Apple ID) or is
            // over quota — the store's contents no longer represent this user's
            // data, so do NOT overwrite local from it. Forget our echo baseline.
            lastData = nil
        default:
            // ServerChange / InitialSyncChange: the store now reflects real
            // remote state, so uploads are safe and there may be data to pull.
            hasSyncedInitialState = true
            pullRemote()
        }
    }

    /// Writes the snapshot to iCloud, unless it matches what we last synced, sync
    /// hasn't reported its initial state yet, or it exceeds the KVS size limit.
    func save(_ snapshot: AppSnapshot) {
        guard isEnabled, hasSyncedInitialState,
              let data = try? Self.encoder.encode(snapshot),
              data != lastData,
              data.count < Self.maxValueBytes else { return }
        lastData = data
        store.setSyncData(data, forKey: Self.key)
        store.synchronize()
    }

    /// Reads the remote snapshot and notifies if it differs from what we last
    /// saw. `lastData` is only advanced on a successful decode, so a malformed
    /// remote value doesn't permanently suppress future good pulls.
    func pullRemote() {
        guard isEnabled,
              let data = store.syncData(forKey: Self.key),
              data != lastData,
              let snapshot = try? JSONDecoder().decode(AppSnapshot.self, from: data) else { return }
        lastData = data
        onRemoteChange?(snapshot)
    }
}

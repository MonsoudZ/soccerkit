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

    private let store: KeyValueSyncStore
    private var observer: NSObjectProtocol?
    /// The last bytes we wrote or read, to suppress our own echoes and no-op
    /// duplicate pulls.
    private var lastData: Data?

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
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pullRemote() }
        }
        store.synchronize()
        pullRemote()
    }

    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    /// Writes the snapshot to iCloud, unless it matches what we last synced.
    func save(_ snapshot: AppSnapshot) {
        guard isEnabled, let data = try? Self.encoder.encode(snapshot), data != lastData else { return }
        lastData = data
        store.setSyncData(data, forKey: Self.key)
        store.synchronize()
    }

    /// Reads the remote snapshot and notifies if it differs from what we last saw.
    func pullRemote() {
        guard isEnabled,
              let data = store.syncData(forKey: Self.key),
              data != lastData else { return }
        lastData = data
        if let snapshot = try? JSONDecoder().decode(AppSnapshot.self, from: data) {
            onRemoteChange?(snapshot)
        }
    }
}

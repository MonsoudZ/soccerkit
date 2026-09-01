import Foundation

/// Remembers, across launches, which version of each record the remote already
/// has — the baseline `SyncRecords.diff` measures local changes against.
///
/// `AppStore` used to hold that baseline only in memory and rebuild it from the
/// local snapshot on every launch, which amounts to declaring "the remote has
/// everything I have" before talking to the remote at all. An edit made while
/// the remote was unreachable was correctly held back for retry, then erased
/// from the next diff by the relaunch — unsynced for good, unless that record
/// happened to be touched again.
///
/// Only fingerprints are stored, not payloads, so this is a small map rather
/// than a second copy of the coach's season. It is per-namespace: two coaches on
/// one device sync against different remotes and must not share a baseline.
struct SyncWatermarkStore {
    private let defaults: UserDefaults
    private let namespace: String

    init(namespace: String?, defaults: UserDefaults = .standard) {
        self.namespace = namespace ?? "default"
        self.defaults = defaults
    }

    private var storageKey: String { "syncWatermark.\(namespace)" }

    /// The stored baseline, or `nil` when this namespace has none yet.
    func load() -> [SyncRecordKey: String]? {
        guard let data = defaults.data(forKey: storageKey),
              let raw = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }

        var result: [SyncRecordKey: String] = [:]
        for (encoded, digest) in raw {
            guard let recordKey = Self.decode(encoded) else { continue }
            result[recordKey] = digest
        }
        return result
    }

    func save(_ digests: [SyncRecordKey: String]) {
        let raw = Dictionary(digests.map { (Self.encode($0.key), $0.value) },
                             uniquingKeysWith: { a, _ in a })
        guard let data = try? JSONEncoder().encode(raw) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// Drops the baseline — the remote's copy is gone, so nothing can be assumed
    /// synced against it any more.
    func clear() {
        defaults.removeObject(forKey: storageKey)
    }

    // MARK: - Key encoding

    // "Type|id", matching how CloudKit record names carry the type.
    private static func encode(_ key: SyncRecordKey) -> String {
        "\(key.type.rawValue)|\(key.id)"
    }

    private static func decode(_ encoded: String) -> SyncRecordKey? {
        let parts = encoded.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let type = SyncRecordType(rawValue: String(parts[0])) else { return nil }
        return SyncRecordKey(type, String(parts[1]))
    }
}

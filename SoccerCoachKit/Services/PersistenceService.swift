import Foundation

/// Abstraction over where the app's snapshot is stored. Keeping this behind a
/// protocol lets the store be initialized with an alternate backend (in-memory
/// for tests and previews, or a future file/CloudKit implementation) without
/// touching the view or store logic.
protocol PersistenceService {
    func load() -> AppSnapshot?
    func save(_ snapshot: AppSnapshot)
}

/// Default persistence backed by `UserDefaults`, storing a JSON-encoded snapshot.
final class UserDefaultsPersistenceService: PersistenceService {
    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String = "SoccerCoachKit.AppSnapshot.v1") {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() -> AppSnapshot? {
        guard
            let data = defaults.data(forKey: storageKey),
            let snapshot = try? JSONDecoder().decode(AppSnapshot.self, from: data)
        else {
            return nil
        }

        return snapshot
    }

    func save(_ snapshot: AppSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

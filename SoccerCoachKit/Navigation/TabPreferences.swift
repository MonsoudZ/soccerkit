import Foundation

/// Owns the coach's customizable "Quick Access" tab bar: Home is always pinned,
/// followed by their chosen sections, then the "More" tab. Persisted so the
/// layout is remembered. Injected at the app root like `ThemeManager`.
@MainActor
final class TabPreferences: ObservableObject {
    /// Always the first tab; never removable.
    static let pinned: AppSection = .dashboard
    /// Quick-access slots besides Home. Kept at 3 so the bar stays Home + 3 +
    /// More (5 tabs) — at 6+, SwiftUI replaces our "More" with its own overflow.
    static let maxFavorites = 3

    private static let storageKey = "favoriteSections.v1"
    private static let fallback: [AppSection] = [.calendar, .roster, .game]

    private let defaults: UserDefaults

    @Published private(set) var favorites: [AppSection] {
        didSet {
            defaults.set(favorites.map(\.rawValue).joined(separator: ","), forKey: Self.storageKey)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.storageKey) {
            let parsed = raw
                .split(separator: ",")
                .compactMap { AppSection(rawValue: String($0)) }
                .filter { $0 != Self.pinned }
            favorites = Self.sanitized(parsed)
        } else {
            favorites = Self.fallback
        }
    }

    // MARK: - Derived

    /// The tabs shown before "More": Home followed by the chosen favorites.
    var quickAccess: [AppSection] { [Self.pinned] + favorites }

    /// Sections not pinned and not favorited — what the "More" tab lists and
    /// what can be added to Quick Access.
    var available: [AppSection] {
        AppSection.allCases.filter { $0 != Self.pinned && !favorites.contains($0) }
    }

    var isFull: Bool { favorites.count >= Self.maxFavorites }

    func isFavorite(_ section: AppSection) -> Bool { favorites.contains(section) }

    // MARK: - Editing

    func add(_ section: AppSection) {
        guard section != Self.pinned, !favorites.contains(section), !isFull else { return }
        favorites.append(section)
    }

    func remove(_ section: AppSection) {
        favorites.removeAll { $0 == section }
    }

    func remove(atOffsets offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
    }

    func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        favorites.move(fromOffsets: offsets, toOffset: destination)
    }

    func resetToDefault() {
        favorites = Self.fallback
    }

    // MARK: - Helpers

    /// Drops the pinned section and duplicates, and caps to the slot count.
    private static func sanitized(_ sections: [AppSection]) -> [AppSection] {
        var seen = Set<AppSection>()
        var result: [AppSection] = []
        for section in sections where section != pinned && !seen.contains(section) {
            seen.insert(section)
            result.append(section)
            if result.count == maxFavorites { break }
        }
        return result
    }
}

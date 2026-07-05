import Foundation

/// The next fixture, shared with the Home Screen widget through the app group.
/// Foundation-only so it compiles into both the app and the widget extension.
struct FixtureSnapshot: Codable, Hashable {
    var teamName: String
    var opponent: String
    var date: Date
    var location: String
    var isHome: Bool
    /// Team accent as a 24-bit RGB hex string (e.g. "4F46E5").
    var accentHex: String

    /// Placeholder used for the widget gallery and previews.
    static let sample = FixtureSnapshot(
        teamName: "Northside Falcons",
        opponent: "Riverside Rovers",
        date: Date(timeIntervalSinceNow: 3 * 24 * 3600),
        location: "Central Park Field 3",
        isHome: true,
        accentHex: "4F46E5"
    )
}

/// Read/write access to the fixture the app shares with its widget, backed by an
/// app-group `UserDefaults` suite so both processes see the same value.
enum WidgetSharedStore {
    static let appGroup = "group.com.monsoudzanaty.SoccerCoachKit"
    private static let key = "nextFixture"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroup)
    }

    static func save(_ fixture: FixtureSnapshot?) {
        guard let defaults else { return }
        if let fixture, let data = try? JSONEncoder().encode(fixture) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    static func load() -> FixtureSnapshot? {
        guard let defaults, let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(FixtureSnapshot.self, from: data)
    }
}

import Foundation

/// The part of a live match that has to outlive the process.
///
/// `GameDayViewModel` is held for the app's lifetime, which covers navigating
/// between sections but not a crash, an eviction while backgrounded, or a
/// force-quit. Losing the clock, the lineup, the sub log and the score at half
/// time loses the thing the screen exists for — and the minutes it was tracking
/// are the basis of the app's fair-play promise, so they can't be reconstructed
/// from memory afterwards.
///
/// Only durable state lives here. The roster and the team's rules are re-read
/// from the store on restore, and the transient UI — which alert is on screen,
/// what the Quick Sub pickers have selected — is rebuilt.
struct GameDaySession: Codable, Equatable {
    /// The team this match was played for. A saved match is only ever restored
    /// onto that team; anything else is a different game.
    var teamID: UUID
    var savedAt: Date
    /// Where the saved clock stops. While the clock runs this is the moment the
    /// banked totals below were last brought up to date, so the interval from
    /// here to now is time the match accrued while the app wasn't there to count
    /// it. `nil` means the clock was paused and nothing is outstanding.
    var runningSince: Date?

    var accumulatedElapsed: TimeInterval
    var elapsedAtPeriodStart: TimeInterval
    var accumulatedPlaying: [UUID: TimeInterval]
    var accumulatedPlayingAtPeriodStart: [UUID: TimeInterval]

    var starterIDs: Set<UUID>
    var playerStatuses: [UUID: GamePlayerStatus]
    var currentPeriod: Int
    var formation: LineupFormation

    var reminders: [SubReminder]
    var subLog: [SubLogEntry]
    var subAlertLeadMinutes: Int

    var teamScore: Int
    var opponentScore: Int
    var opponentName: String
    var linkedGameID: UUID?
}

/// Where a live match is kept between launches.
///
/// Per-coach, like every other partitioned store in the app: the sub log carries
/// players' names, so one account's match must not be readable by another
/// signed in on the same device.
protocol GameDaySessionStore: AnyObject {
    func load() -> GameDaySession?
    func save(_ session: GameDaySession)
    func clear()
}

final class UserDefaultsGameDaySessionStore: GameDaySessionStore {
    private let defaults: UserDefaults
    private let key: String

    init(namespace: String?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.key = "gameDaySession.\(namespace ?? "default")"
    }

    func load() -> GameDaySession? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(GameDaySession.self, from: data)
    }

    func save(_ session: GameDaySession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() { defaults.removeObject(forKey: key) }
}

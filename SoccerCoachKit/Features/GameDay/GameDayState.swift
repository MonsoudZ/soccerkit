import Foundation

/// The restorable state of a live match.
///
/// Deliberately *not* part of `AppSnapshot`. A match in progress belongs to the
/// device running it, not to the coach's synced data: putting it in the snapshot
/// would push every substitution and goal through the sync diff, and hand a
/// second device a match it isn't the one refereeing.
struct GameDaySnapshot: Codable {
    /// When this was written, so yesterday's match isn't resurrected today.
    var savedAt: Date
    /// The team the match belongs to. `prepareIfNeeded` compares it against the
    /// selected team to decide whether to resume or start fresh, so restoring it
    /// is what stops a resumed match from being wiped when the view appears.
    var teamID: UUID?

    /// The wall-clock instant the current running interval began; `nil` when the
    /// clock is stopped.
    ///
    /// The live clock runs on `mach_continuous_time` — immune to NTP, DST, and
    /// manual clock changes, which is what a game clock needs. But it restarts at
    /// boot, so a monotonic anchor means nothing to the next launch. Persisting
    /// the wall-clock instant instead lets a relaunch work out how much of the
    /// match it missed, and re-anchor to the monotonic clock from there.
    var runningSince: Date?

    var accumulatedElapsed: TimeInterval
    var accumulatedPlaying: [UUID: TimeInterval]
    var accumulatedPlayingAtPeriodStart: [UUID: TimeInterval]
    var elapsedAtPeriodStart: TimeInterval

    var starterIDs: Set<UUID>
    var playerStatuses: [UUID: GamePlayerStatus]
    var currentPeriod: Int
    var formation: LineupFormation

    var reminders: [SubReminder]
    var subLog: [SubLogEntry]
    var subAlertLeadMinutes: Int
    var newReminderMinute: Int

    var teamScore: Int
    var opponentScore: Int
    var opponentName: String
    var linkedGameID: UUID?

    /// Whether there is a match here worth restoring. A lineup sitting at kickoff
    /// with a stopped clock is indistinguishable from a fresh one, so resuming it
    /// would only be a chance to get something wrong.
    var hasMatchInProgress: Bool {
        runningSince != nil
            || accumulatedElapsed > 0
            || !subLog.isEmpty
            || teamScore > 0
            || opponentScore > 0
    }

    /// A match that hasn't started. Used to blank the in-memory state when
    /// switching coaches, so one coach's live match can't bleed into another's
    /// session on a shared device.
    static func empty(at date: Date) -> GameDaySnapshot {
        GameDaySnapshot(
            savedAt: date, teamID: nil, runningSince: nil,
            accumulatedElapsed: 0, accumulatedPlaying: [:],
            accumulatedPlayingAtPeriodStart: [:], elapsedAtPeriodStart: 0,
            starterIDs: [], playerStatuses: [:], currentPeriod: 1, formation: .balanced,
            reminders: [], subLog: [], subAlertLeadMinutes: 1, newReminderMinute: 15,
            teamScore: 0, opponentScore: 0, opponentName: "Opponent", linkedGameID: nil
        )
    }
}

/// Where an in-progress match is kept between launches. Behind a protocol so the
/// view model can be exercised without touching `UserDefaults` — and so the
/// default is an isolated in-memory store rather than shared global state.
protocol GameDayStateStore: AnyObject {
    func load() -> GameDaySnapshot?
    func save(_ snapshot: GameDaySnapshot)
    func clear()
    /// Partitions saved matches by signed-in coach, matching how `AppSnapshot`
    /// and CloudKit zones are namespaced. `nil` is the guest namespace.
    func setNamespace(_ namespace: String?)
}

/// The default for anything that isn't the running app: keeps a match for the
/// lifetime of the object and no longer. `GameDayViewModel` defaults to this so
/// a test — or a preview — can never pick up a match left behind by something
/// else; `AppStore` passes the `UserDefaults`-backed store explicitly.
final class InMemoryGameDayStateStore: GameDayStateStore {
    private var stored: [String: GameDaySnapshot] = [:]
    private var namespace = ""

    init() {}

    func load() -> GameDaySnapshot? { stored[namespace] }
    func save(_ snapshot: GameDaySnapshot) { stored[namespace] = snapshot }
    func clear() { stored[namespace] = nil }
    func setNamespace(_ namespace: String?) { self.namespace = namespace ?? "" }
}

/// Persists the live match as JSON in `UserDefaults`. It's a single small record
/// that is rewritten on each state transition and read once at launch, which is
/// exactly what `UserDefaults` is good at — unlike the whole-app snapshot.
final class UserDefaultsGameDayStateStore: GameDayStateStore {
    private let defaults: UserDefaults
    private let baseKey: String
    private var namespace: String?
    private var storageKey: String { namespace.map { "\(baseKey).\($0)" } ?? baseKey }

    init(defaults: UserDefaults = .standard,
         namespace: String? = nil,
         baseKey: String = "SoccerCoachKit.GameDayState.v1") {
        self.defaults = defaults
        self.baseKey = baseKey
        self.namespace = namespace
    }

    func setNamespace(_ namespace: String?) { self.namespace = namespace }

    func load() -> GameDaySnapshot? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        // An undecodable match is dropped rather than backed up the way
        // `AppSnapshot` is: this is one match's clock, reconstructible by the
        // coach in seconds, not the season's data.
        return try? JSONDecoder().decode(GameDaySnapshot.self, from: data)
    }

    func save(_ snapshot: GameDaySnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else {
            assertionFailure("Failed to encode GameDaySnapshot")
            return
        }
        defaults.set(data, forKey: storageKey)
    }

    func clear() { defaults.removeObject(forKey: storageKey) }
}

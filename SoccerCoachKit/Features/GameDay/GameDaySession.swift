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

/// The saved match, sealed at rest.
///
/// Namespacing the key separates two coaches inside a working app; it is not
/// confidentiality, and this blob needs some. `SubLogEntry` carries `outName`
/// and `inName` — children's names, as displayed — and `playerStatuses` records
/// which of them is `injured`. Written as plain JSON, which is how this started,
/// a squad list and who was hurt sat in readable text inside any unencrypted
/// device backup: the same exposure `SnapshotCipher` exists to close for the
/// roster, through a store that had been overlooked.
///
/// It shares the roster's key deliberately — same app, same device, same threat
/// — so there is one key to hold and one to lose.
final class UserDefaultsGameDaySessionStore: GameDaySessionStore {
    private let defaults: UserDefaults
    private let key: String
    private let cipher: SnapshotCipher

    init(namespace: String?,
         defaults: UserDefaults = .standard,
         cipher: SnapshotCipher = KeychainSnapshotCipher()) {
        self.defaults = defaults
        self.key = "gameDaySession.\(namespace ?? "default")"
        self.cipher = cipher
    }

    func load() -> GameDaySession? {
        guard let data = defaults.data(forKey: key) else { return nil }

        if let plaintext = try? cipher.open(data) {
            return try? JSONDecoder().decode(GameDaySession.self, from: plaintext)
        }

        // Not sealed, or not sealed with a key we hold. A match saved before
        // encryption is the first case: read it, then write it back sealed
        // rather than leave the squad's names lying in the clear. A coach can
        // be mid-match across the upgrade, so losing it here isn't an option.
        guard let session = try? JSONDecoder().decode(GameDaySession.self, from: data) else {
            return nil
        }
        save(session)
        return session
    }

    /// Writes the match, sealed. A save that can't be sealed is dropped rather
    /// than written in the clear — the same call the roster makes, for the same
    /// reason.
    ///
    /// There is no retry queue behind this because a live match doesn't need
    /// one: every sub, goal, period change, and clock start/pause saves, so the
    /// next mutation is the retry, and what it writes is newer anyway. Any
    /// previously sealed match is left in place rather than cleared, so a failed
    /// save costs the most recent moments and not the whole match.
    func save(_ session: GameDaySession) {
        guard let encoded = try? JSONEncoder().encode(session),
              let sealed = try? cipher.seal(encoded) else { return }
        defaults.set(sealed, forKey: key)
    }

    func clear() { defaults.removeObject(forKey: key) }
}

import Foundation

/// Owns the ephemeral game-day state: the clock, lineup, substitutions, and
/// per-player status. It is seeded from the store's roster/age-group settings
/// via `reset(with:)` on appear and whenever the selected team changes.
@MainActor
final class GameDayViewModel: ObservableObject {
    // Configuration snapshot sourced from the store.
    @Published private(set) var roster: [Player] = []
    @Published private(set) var playersOnField = 0
    @Published private(set) var defaultGameMinutes = 0
    @Published private(set) var defaultMinimumMinutes = 0
    @Published private(set) var periodFormat: PeriodFormat = .halves
    private var teamID: UUID?
    private var teamName = ""
    private var accentHex = "4F46E5"

    // MARK: Wall-clock timekeeping
    // The clock is derived from timestamps, not tick counts, so it stays
    // accurate across missed ticks (app backgrounded, view off-screen, phone
    // locked). `accumulated*` hold time banked up to the last `settle`;
    // `runAnchor` marks when the current running interval began.
    private var accumulatedElapsed: TimeInterval = 0
    private var accumulatedPlaying: [UUID: TimeInterval] = [:]
    private var accumulatedPlayingAtPeriodStart: [UUID: TimeInterval] = [:]
    private var elapsedAtPeriodStart: TimeInterval = 0
    /// Monotonic seconds marking when the current running interval began.
    private var runAnchor: TimeInterval?
    /// Source of monotonic seconds (injectable for testing).
    private let now: () -> TimeInterval
    /// Schedules background local notifications for pending sub reminders.
    private let notifier = GameDayNotifier()

    // Game state.
    @Published var starterIDs: Set<UUID> = []
    @Published var currentPeriod = 1
    @Published var isRunning = false
    @Published var reminders: [SubReminder] = []
    @Published var subLog: [SubLogEntry] = []
    @Published var playerStatuses: [UUID: GamePlayerStatus] = [:]
    @Published var newReminderMinute = 15
    @Published var selectedOutPlayerID: UUID?
    @Published var selectedInPlayerID: UUID?
    @Published var activeReminder: SubReminder?
    @Published var showReminder = false
    @Published var activePreAlert: SubReminder?
    @Published var showPreAlert = false
    /// How many minutes before a reminder's minute the early heads-up fires.
    @Published var subAlertLeadMinutes = 1
    @Published var formation: LineupFormation = .balanced

    // Live scoreboard (surfaced on the Game Day screen and the Live Activity).
    @Published var teamScore = 0
    @Published var opponentScore = 0
    @Published var opponentName = "Opponent"
    /// The scheduled game this live match writes its score into, if any.
    @Published var linkedGameID: UUID?

    /// `now` is injectable purely for testing; production uses a monotonic
    /// source. `nonisolated` so the app-wide `AppStore` can own an instance.
    nonisolated init(now: @escaping () -> TimeInterval = GameDayViewModel.monotonicNow) {
        self.now = now
    }

    /// Monotonic seconds that keep advancing while the device sleeps (locked
    /// phone) and are immune to wall-clock changes (NTP/DST/manual), so the game
    /// clock can't jump or run backward mid-match.
    nonisolated static func monotonicNow() -> TimeInterval {
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1_000_000_000
    }

    // MARK: - Wall-clock derived values

    private var liveInterval: TimeInterval {
        guard let anchor = runAnchor else { return 0 }
        return max(0, now() - anchor)
    }

    /// Total elapsed game time in whole seconds.
    var elapsedSeconds: Int { Int(accumulatedElapsed + liveInterval) }

    /// Each roster player's playing time in whole seconds, including the live
    /// interval for players currently on the field and available.
    var playingSeconds: [UUID: Int] {
        let live = liveInterval
        let running = runAnchor != nil
        var result: [UUID: Int] = [:]
        for player in roster {
            var total = accumulatedPlaying[player.id] ?? 0
            if running, starterIDs.contains(player.id), playerStatuses[player.id, default: .available] == .available {
                total += live
            }
            result[player.id] = Int(total)
        }
        return result
    }

    /// Banks the running interval into the accumulators and re-anchors. Must be
    /// called before any change to who is playing or whether the clock runs, so
    /// time accrues under the configuration that was actually in effect.
    func settle() {
        guard let anchor = runAnchor else { return }
        let current = now()
        let delta = current - anchor
        runAnchor = current
        guard delta > 0 else { return }
        accumulatedElapsed += delta
        for id in starterIDs where playerStatuses[id, default: .available] == .available {
            accumulatedPlaying[id, default: 0] += delta
        }
    }

    // MARK: - Configuration

    /// Refresh the roster/age-group snapshot from the store and reset the game.
    func reset(with store: AppStore) {
        loadConfiguration(from: store)
        roster = store.roster
        resetLineup()
    }

    /// Loads the team's game rules (field size, game length, minimum minutes,
    /// period format) from the store. Kept separate from `reset` so an
    /// in-progress game can pick up mid-match settings changes without being
    /// wiped. `teamID` is tracked as `selectedTeamID` — the same value
    /// `prepareIfNeeded` compares against — to avoid drift.
    private func loadConfiguration(from store: AppStore) {
        let team = store.selectedTeam
        teamID = store.selectedTeamID
        teamName = team.name
        accentHex = team.accent.hex
        playersOnField = team.ageGroup.playersOnField
        defaultGameMinutes = team.ageGroup.defaultGameMinutes
        defaultMinimumMinutes = team.defaultMinimumMinutes
        periodFormat = team.periodFormat
    }

    /// Called when the Game Day view appears. Only sets up a fresh game the
    /// first time, or when the selected team changed; otherwise it keeps the
    /// in-progress game intact (just reconciling the roster) so switching tabs
    /// mid-match doesn't wipe the clock, minutes, or lineup.
    func prepareIfNeeded(with store: AppStore) {
        // Reflect goals scored from the Live Activity's interactive buttons back
        // into the scoreboard (and the linked game's report).
        activity.onScoreChange = { [weak self] team, opponent in
            guard let self else { return }
            self.teamScore = team
            self.opponentScore = opponent
            self.persistScore(in: store)
        }
        if teamID != store.selectedTeamID {
            reset(with: store)
        } else {
            syncRoster(with: store)
        }
    }

    /// Reconciles an in-progress game with the store's roster after a mid-game
    /// add/edit/delete, without disturbing the clock, minutes, or lineup of
    /// players who are still on the team.
    func syncRoster(with store: AppStore) {
        // Pick up mid-match rule changes (age group, period format, minimum
        // minutes) even when the roster itself is unchanged.
        loadConfiguration(from: store)

        // Bank the running interval before any lineup change below.
        settle()

        // If the field size shrank (e.g. age group lowered mid-game), trim the
        // starting lineup so extra starters don't keep accruing time while being
        // dropped from the pitch diagram.
        if starterIDs.count > playersOnField {
            let kept = roster.filter { starterIDs.contains($0.id) }.prefix(playersOnField).map(\.id)
            starterIDs = Set(kept)
            normalizeSelections()
        }

        let updated = store.roster
        guard updated != roster else { return }

        let validIDs = Set(updated.map(\.id))
        roster = updated

        // Drop state for players no longer on the roster.
        starterIDs = starterIDs.intersection(validIDs)
        accumulatedPlaying = accumulatedPlaying.filter { validIDs.contains($0.key) }
        accumulatedPlayingAtPeriodStart = accumulatedPlayingAtPeriodStart.filter { validIDs.contains($0.key) }
        playerStatuses = playerStatuses.filter { validIDs.contains($0.key) }
        reminders.removeAll { !validIDs.contains($0.outPlayerID) || !validIDs.contains($0.inPlayerID) }

        // Seed state for newly added players.
        for player in updated {
            if accumulatedPlaying[player.id] == nil { accumulatedPlaying[player.id] = 0 }
            if accumulatedPlayingAtPeriodStart[player.id] == nil { accumulatedPlayingAtPeriodStart[player.id] = accumulatedPlaying[player.id] ?? 0 }
            if playerStatuses[player.id] == nil { playerStatuses[player.id] = .available }
        }

        normalizeSelections()
    }

    // MARK: - Derived state

    var starterPlayers: [Player] {
        roster.filter { starterIDs.contains($0.id) }
    }

    var availableStarterPlayers: [Player] {
        starterPlayers.filter { status(for: $0) == .available }
    }

    var benchPlayers: [Player] {
        roster.filter { !starterIDs.contains($0.id) }
    }

    var availableBenchPlayers: [Player] {
        benchPlayers.filter { status(for: $0) == .available }
    }

    var periodSeconds: Int {
        // Floor the whole period interval once, so it can't read a second ahead
        // of the game clock from independently truncating both values.
        Int(max(0, accumulatedElapsed + liveInterval - elapsedAtPeriodStart))
    }

    var activeReminderText: String {
        guard let reminder = activeReminder else { return "" }
        let outName = playerName(reminder.outPlayerID)
        let inName = playerName(reminder.inPlayerID)
        return "\(formatClock(reminder.minute * 60)): put \(inName) in for \(outName)."
    }

    var activePreAlertText: String {
        guard let reminder = activePreAlert else { return "" }
        let outName = playerName(reminder.outPlayerID)
        let inName = playerName(reminder.inPlayerID)
        let lead = max(0, reminder.minute * 60 - elapsedSeconds)
        return "In \(formatClock(lead)) at \(reminder.minute)': \(inName) in for \(outName). Get them ready."
    }

    var canUndoLastSub: Bool {
        guard let last = subLog.first else { return false }
        return starterIDs.contains(last.inPlayerID) && !starterIDs.contains(last.outPlayerID)
    }

    func status(for player: Player) -> GamePlayerStatus {
        playerStatuses[player.id, default: .available]
    }

    func playerName(_ id: UUID) -> String {
        roster.first { $0.id == id }?.name ?? "Player"
    }

    // MARK: - Periods

    var periodCount: Int { periodFormat.periodCount }

    var isLastPeriod: Bool { currentPeriod >= periodCount }

    var currentPeriodLabel: String { periodFormat.label(forPeriod: currentPeriod) }

    /// Label for the button that ends the current period.
    var advancePeriodLabel: String {
        guard !isLastPeriod else { return "Final \(periodFormat == .halves ? "Half" : "Quarter")" }
        if periodFormat == .halves && currentPeriod == 1 { return "Halftime" }
        return "End \(currentPeriodLabel)"
    }

    // MARK: - Clock

    func tick() {
        guard isRunning else { return }
        // Bank elapsed time (also catches up after missed ticks) and refresh the
        // wall-clock-derived displays, then check reminders.
        settle()
        objectWillChange.send()
        processReminderAlerts()
    }

    private var isShowingAlert: Bool { showReminder || showPreAlert }

    /// Surfaces at most one reminder alert at a time. A reminder that comes due
    /// while another alert is still on screen keeps its flags untouched and
    /// stays pending, so nothing is overwritten and silently lost; the next one
    /// is presented when the current alert is dismissed.
    private func processReminderAlerts() {
        guard !isShowingAlert else { return }

        // Exact-minute alerts take priority over heads-ups.
        if let index = earliestReminderIndex(where: { !$0.triggered && elapsedSeconds >= $0.minute * 60 }) {
            reminders[index].triggered = true
            activeReminder = reminders[index]
            showReminder = true
            return
        }

        let leadSeconds = max(0, subAlertLeadMinutes) * 60
        if let index = earliestReminderIndex(where: {
            !$0.preAlertTriggered && !$0.triggered
                && elapsedSeconds >= $0.minute * 60 - leadSeconds
                && elapsedSeconds < $0.minute * 60
        }) {
            reminders[index].preAlertTriggered = true
            activePreAlert = reminders[index]
            showPreAlert = true
        }
    }

    /// Index of the earliest-scheduled reminder matching `predicate`, so stacked
    /// reminders surface in chronological order.
    private func earliestReminderIndex(where predicate: (SubReminder) -> Bool) -> Int? {
        reminders.enumerated()
            .filter { predicate($0.element) }
            .min(by: { $0.element.minute < $1.element.minute })?
            .offset
    }

    /// Records the sub for the active reminder (or keeps the lineup), then shows
    /// the next pending alert if one queued up behind it.
    func acknowledgeReminder(record: Bool) {
        if record, let reminder = activeReminder {
            applySubstitution(reminder)
        }
        activeReminder = nil
        showReminder = false
        rescheduleNotifications()
        presentNextPendingAlert()
    }

    func dismissPreAlert() {
        activePreAlert = nil
        showPreAlert = false
        presentNextPendingAlert()
    }

    private func presentNextPendingAlert() {
        // Defer so the current alert finishes dismissing before the next one
        // (which may reuse the same isPresented binding) is presented.
        DispatchQueue.main.async { [weak self] in
            self?.processReminderAlerts()
        }
    }

    // MARK: - Background notifications

    /// Prompts for notification permission (once) so reminders can alert the
    /// coach while the app is backgrounded or the phone is locked.
    func requestNotificationAuthorization() {
        notifier.requestAuthorization()
    }

    /// Rebuilds the scheduled background notifications from the pending reminders
    /// and the current clock. Called whenever the clock state or reminders
    /// change. When the clock isn't running there's no wall-clock mapping, so
    /// all notifications are cleared.
    func rescheduleNotifications() {
        guard isRunning else {
            notifier.cancelAll()
            return
        }

        let elapsed = elapsedSeconds
        let lead = max(0, subAlertLeadMinutes)
        var items: [GameDayNotifier.PendingNotification] = []

        for reminder in reminders where !reminder.triggered {
            let dueSeconds = TimeInterval(reminder.minute * 60 - elapsed)
            let inName = playerName(reminder.inPlayerID)
            let outName = playerName(reminder.outPlayerID)

            if dueSeconds >= 1 {
                items.append(.init(
                    id: "\(reminder.id).exact",
                    secondsFromNow: dueSeconds,
                    title: "Substitution Time",
                    body: "Put \(inName) in for \(outName) (\(reminder.minute)')."
                ))
            }

            if lead > 0, !reminder.preAlertTriggered {
                let preSeconds = dueSeconds - TimeInterval(lead * 60)
                if preSeconds >= 1 {
                    items.append(.init(
                        id: "\(reminder.id).pre",
                        secondsFromNow: preSeconds,
                        title: "Sub Coming Up",
                        body: "In \(lead) min: \(inName) for \(outName). Get them ready."
                    ))
                }
            }
        }

        notifier.reschedule(items)
    }

    func start() {
        guard !isRunning else { return }
        runAnchor = now()
        isRunning = true
        rescheduleNotifications()
        // Begin (or resume) the Live Activity when the clock starts running.
        activity.start(teamName: teamName, opponentName: opponentName, accentHex: accentHex,
                       teamScore: teamScore, opponentScore: opponentScore,
                       periodLabel: currentPeriodLabel, isRunning: true, elapsed: elapsedSeconds)
    }

    func pause() {
        guard isRunning else { return }
        settle()
        runAnchor = nil
        isRunning = false
        rescheduleNotifications()
        refreshActivity()
    }

    // MARK: Live scoreboard

    var isLinkedToGame: Bool { linkedGameID != nil }

    func scoreTeam(_ delta: Int, in store: AppStore) {
        teamScore = max(0, teamScore + delta)
        persistScore(in: store)
        refreshActivity()
    }

    func scoreOpponent(_ delta: Int, in store: AppStore) {
        opponentScore = max(0, opponentScore + delta)
        persistScore(in: store)
        refreshActivity()
    }

    /// Links (or unlinks) the live match to a scheduled game so the score is
    /// written straight into that game's post-game report. Linking adopts the
    /// game's opponent, and seeds the scoreboard from any score already recorded
    /// before writing the current score back.
    func linkGame(_ id: UUID?, in store: AppStore) {
        linkedGameID = id
        guard let id, let game = store.games.first(where: { $0.id == id }) else { return }
        opponentName = game.opponent
        if let recorded = game.teamScore { teamScore = recorded }
        if let recorded = game.opponentScore { opponentScore = recorded }
        persistScore(in: store)
        refreshActivity()
    }

    /// Mirrors the live score into the linked game's record. No-op when unlinked.
    private func persistScore(in store: AppStore) {
        guard let id = linkedGameID,
              var game = store.games.first(where: { $0.id == id }) else { return }
        game.teamScore = teamScore
        game.opponentScore = opponentScore
        store.updateGame(game)
    }

    // MARK: Live Activity

    private let activity = GameActivityController.shared

    /// Pushes the current match state to a running Live Activity (no-op if none).
    private func refreshActivity() {
        guard activity.isActive else { return }
        activity.update(teamScore: teamScore, opponentScore: opponentScore,
                        periodLabel: currentPeriodLabel, isRunning: isRunning, elapsed: elapsedSeconds)
    }

    private func endActivity() {
        activity.end()
    }

    private func resetLineup() {
        runAnchor = nil
        isRunning = false
        accumulatedElapsed = 0
        elapsedAtPeriodStart = 0
        reminders.removeAll()
        subLog.removeAll()
        playerStatuses = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, GamePlayerStatus.available) })
        accumulatedPlaying = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, TimeInterval(0)) })
        accumulatedPlayingAtPeriodStart = accumulatedPlaying
        starterIDs = Set(roster.prefix(playersOnField).map(\.id))
        currentPeriod = 1
        teamScore = 0
        opponentScore = 0
        opponentName = "Opponent"
        linkedGameID = nil
        normalizeSelections()
        rescheduleNotifications()
        endActivity()
    }

    func resetGameClock() {
        runAnchor = nil
        isRunning = false
        accumulatedElapsed = 0
        elapsedAtPeriodStart = 0
        currentPeriod = 1
        accumulatedPlaying = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, TimeInterval(0)) })
        accumulatedPlayingAtPeriodStart = accumulatedPlaying
        // Restore the starting lineup so it matches the now-empty sub log.
        playerStatuses = Dictionary(uniqueKeysWithValues: roster.map { ($0.id, GamePlayerStatus.available) })
        starterIDs = Set(roster.prefix(playersOnField).map(\.id))
        reminders = reminders.map { reminder in
            var updated = reminder
            updated.triggered = false
            updated.preAlertTriggered = false
            return updated
        }
        subLog.removeAll()
        teamScore = 0
        opponentScore = 0
        normalizeSelections()
        rescheduleNotifications()
        endActivity()
    }

    func advancePeriod() {
        guard !isLastPeriod else { return }
        settle()
        runAnchor = nil
        isRunning = false
        currentPeriod += 1
        elapsedAtPeriodStart = accumulatedElapsed
        accumulatedPlayingAtPeriodStart = accumulatedPlaying
        rescheduleNotifications()
        refreshActivity()
    }

    func resetPeriodClock() {
        runAnchor = nil
        isRunning = false
        // Rewind the clock and minutes to this period's start snapshot.
        accumulatedElapsed = elapsedAtPeriodStart
        accumulatedPlaying = accumulatedPlayingAtPeriodStart
        let elapsed = elapsedSeconds
        reminders = reminders.map { reminder in
            var updated = reminder
            let due = elapsed >= reminder.minute * 60
            updated.triggered = due
            // Only suppress the heads-up once the exact minute has passed; a
            // reminder still ahead of us gets a fresh chance at its pre-alert,
            // even if we reset into its lead window.
            updated.preAlertTriggered = due
            return updated
        }
        rescheduleNotifications()
        refreshActivity()
    }

    // MARK: - Lineup

    func moveToBench(_ player: Player) {
        settle()
        starterIDs.remove(player.id)
        normalizeSelections()
    }

    func moveToStarter(_ player: Player) {
        guard starterIDs.count < playersOnField else { return }
        guard status(for: player) == .available else { return }
        settle()
        starterIDs.insert(player.id)
        normalizeSelections()
    }

    func setPlayerStatus(_ player: Player, _ status: GamePlayerStatus) {
        settle()
        playerStatuses[player.id] = status

        if status != .available {
            starterIDs.remove(player.id)
        } else if starterIDs.isEmpty {
            starterIDs.insert(player.id)
        }

        normalizeSelections()
    }

    // MARK: - Helpers

    func normalizeSelections() {
        if selectedOutPlayerID == nil || !availableStarterPlayers.contains(where: { $0.id == selectedOutPlayerID }) {
            selectedOutPlayerID = availableStarterPlayers.first?.id
        }

        if selectedInPlayerID == nil || !availableBenchPlayers.contains(where: { $0.id == selectedInPlayerID }) {
            selectedInPlayerID = availableBenchPlayers.first?.id
        }
    }
}

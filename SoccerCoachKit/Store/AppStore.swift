import CoreGraphics
import Foundation
import WidgetKit

/// App-wide source of truth. Holds the published domain collections and the
/// intents that mutate them, delegating durability to a `PersistenceService`.
/// `@MainActor` enforces the invariant that all state access happens on the
/// main thread (persistence itself encodes/writes on a background queue).
@MainActor
final class AppStore: ObservableObject {
    @Published var teams: [Team] {
        didSet { persist() }
    }
    @Published var players: [Player] {
        didSet { persist() }
    }
    @Published var drills: [Drill] {
        didSet { persist() }
    }
    @Published var sessions: [TrainingSession] {
        didSet {
            if sessions.map(scheduleKey) != oldValue.map(scheduleKey) { remindersDirty = true }
            persist()
        }
    }
    @Published var diagrams: [TacticsDiagram] {
        didSet { persist() }
    }
    @Published var games: [GameEvent] {
        didSet {
            if games.map(scheduleKey) != oldValue.map(scheduleKey) { remindersDirty = true }
            persist()
        }
    }
    @Published var events: [TeamEvent] {
        didSet {
            if events.map(scheduleKey) != oldValue.map(scheduleKey) { remindersDirty = true }
            persist()
        }
    }
    /// The time-bounded player↔team joins that replaced `Player.teamID`.
    @Published var memberships: [RosterMembership] {
        didSet { persist() }
    }
    /// Humans (identity/contact/medical), kept in sync with players by the store.
    @Published var people: [Person] {
        didSet { persist() }
    }
    /// Authenticatable identities, optional per Person.
    @Published var userAccounts: [UserAccount] {
        didSet { persist() }
    }
    /// Tenant boundaries (the personal org is always present).
    @Published var organizations: [Organization] {
        didSet { persist() }
    }
    /// `(person, org, roles)` joins — the role model.
    @Published var orgMemberships: [OrgMembership] {
        didSet { persist() }
    }
    /// User/org-owned evaluation templates (built-ins live in code; see
    /// `allFormTemplates`).
    @Published var formTemplates: [FormTemplate] {
        didSet { persist() }
    }
    /// Filled-in evaluation responses — the generic engine's data.
    @Published var formInstances: [FormInstance] {
        didSet { persist() }
    }

    /// Set when a schedule-affecting change (a game/session/event added, removed,
    /// or rescheduled) happens, so `persist()` refreshes reminders once — rather
    /// than on every attendance tap, RSVP, or score change.
    private var remindersDirty = false

    // Stable projections of the fields that determine *when* a reminder fires
    // and *what it says*, so renaming an opponent/session/event refreshes the
    // scheduled notification's text too.
    private func scheduleKey(_ game: GameEvent) -> String { "\(game.id)@\(game.date.timeIntervalSinceReferenceDate)@\(game.opponent)" }
    private func scheduleKey(_ session: TrainingSession) -> String { "\(session.id)@\(session.date.timeIntervalSinceReferenceDate)@\(session.title)" }
    private func scheduleKey(_ event: TeamEvent) -> String { "\(event.id)@\(event.date.timeIntervalSinceReferenceDate)@\(event.endDate?.timeIntervalSinceReferenceDate ?? 0)@\(event.title)" }
    @Published var selectedTeamID: UUID {
        didSet { persist() }
    }

    private let persistence: PersistenceService
    private let cloudKit: CloudKitSyncService?
    /// The record set last mirrored to CloudKit, so each persist can push only
    /// what changed.
    private var lastSyncedRecords: [SyncRecord] = []
    /// True while applying a remote change, so it isn't re-uploaded.
    private var isApplyingRemote = false

    /// Whether iCloud (CloudKit) sync is on, so the coach's data follows them
    /// across devices with record-level merge.
    @Published var cloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cloudSyncEnabled, forKey: "iCloudSyncEnabled")
            if cloudSyncEnabled {
                cloudKit?.start()
                lastSyncedRecords = SyncRecords.records(from: snapshot)
                syncLocalChanges()
            } else {
                cloudKit?.stop()
                syncStatus = .off
            }
        }
    }

    /// Where CloudKit sync stands, surfaced in Settings so sync isn't silent.
    @Published private(set) var syncStatus: SyncStatus = .off

    /// Re-attempts sync after a failure or once an iCloud account is available.
    func retrySync() {
        guard cloudSyncEnabled else { return }
        cloudKit?.start()
    }

    private let scheduleNotifier = ScheduleNotifier()

    /// Whether the coach opted into reminders for upcoming games/practices.
    @Published var eventRemindersEnabled: Bool {
        didSet {
            UserDefaults.standard.set(eventRemindersEnabled, forKey: "eventRemindersEnabled")
            if eventRemindersEnabled {
                scheduleNotifier.requestAuthorization()
                refreshEventReminders()
            } else {
                scheduleNotifier.cancelAll()
            }
        }
    }

    /// Minutes before an event to fire its reminder (0 = at start).
    @Published var reminderLeadMinutes: Int {
        didSet {
            UserDefaults.standard.set(reminderLeadMinutes, forKey: "reminderLeadMinutes")
            refreshEventReminders()
        }
    }

    /// Reschedules local notifications for upcoming games, practices, and events.
    /// No-op (beyond clearing) when reminders are off; never prompts for
    /// permission here — that happens only when the coach enables the toggle.
    func refreshEventReminders() {
        guard eventRemindersEnabled else {
            scheduleNotifier.cancelAll()
            return
        }
        let planned = ScheduleReminderPlanner.reminders(
            games: games,
            sessions: sessions,
            events: events,
            teamName: { [weak self] in self?.teamName(for: $0) ?? "" },
            leadMinutes: reminderLeadMinutes,
            now: Date()
        )
        scheduleNotifier.apply(planned)
    }

    /// The live game-day session. Held here (app-lifetime) so an in-progress
    /// match survives navigating between sections on any device — including the
    /// iPhone, where the detail view is torn down on section changes. It is not
    /// `@Published`, so its per-second clock updates don't re-render the rest of
    /// the app; `GameDayView` observes it directly.
    let gameDay = GameDayViewModel()

    init(snapshot: AppSnapshot,
         persistence: PersistenceService = UserDefaultsPersistenceService(),
         cloudKit: CloudKitSyncService? = nil) {
        self.teams = snapshot.teams
        self.players = snapshot.players
        self.drills = snapshot.drills
        self.sessions = snapshot.sessions
        self.diagrams = snapshot.diagrams
        self.games = snapshot.games
        self.events = snapshot.events
        self.memberships = snapshot.memberships
        self.people = snapshot.people
        self.userAccounts = snapshot.userAccounts
        self.organizations = snapshot.organizations
        self.orgMemberships = snapshot.orgMemberships
        self.formTemplates = snapshot.formTemplates
        self.formInstances = snapshot.formInstances
        self.selectedTeamID = snapshot.teams.contains(where: { $0.id == snapshot.selectedTeamID }) ? snapshot.selectedTeamID : (snapshot.teams.first?.id ?? snapshot.selectedTeamID)
        self.dataVersion = snapshot.dataVersion
        self.persistence = persistence
        self.cloudKit = cloudKit
        self.cloudSyncEnabled = (UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool) ?? (cloudKit != nil)
        self.eventRemindersEnabled = UserDefaults.standard.bool(forKey: "eventRemindersEnabled")
        self.reminderLeadMinutes = (UserDefaults.standard.object(forKey: "reminderLeadMinutes") as? Int) ?? 60
        self.lastSyncedRecords = SyncRecords.records(from: snapshot)
        publishWidgetData()
        if let cloudKit {
            cloudKit.snapshotProvider = { [weak self] in self?.snapshot ?? snapshot }
            cloudKit.applyRemoteChanges = { [weak self] upserts, deletes in
                self?.applyRemoteChanges(upserts: upserts, deletes: deletes)
            }
            cloudKit.onStatusChange = { [weak self] status in
                self?.syncStatus = status
            }
            if cloudSyncEnabled { cloudKit.start() }
        }
    }

    /// Applies record-level changes fetched from CloudKit, without re-uploading them.
    private func applyRemoteChanges(upserts: [SyncRecord], deletes: [SyncRecordKey]) {
        var updated = snapshot
        for record in upserts { SyncRecords.apply(record, to: &updated) }
        for key in deletes { SyncRecords.delete(type: key.type, id: key.id, from: &updated) }
        isApplyingRemote = true
        restore(updated, adoptVersion: true)
        isApplyingRemote = false
    }

    /// Pushes local record changes to CloudKit (diffed against the last sync).
    private func syncLocalChanges() {
        guard let cloudKit, cloudSyncEnabled else { return }
        let current = SyncRecords.records(from: snapshot)
        defer { lastSyncedRecords = current }
        guard !isApplyingRemote else { return } // remote change already synced
        let (upserts, deletes) = SyncRecords.diff(from: lastSyncedRecords, to: current)
        if !upserts.isEmpty || !deletes.isEmpty {
            cloudKit.push(upserts: upserts, deletes: deletes)
        }
    }

    /// The store used at launch: persisted snapshot if present and readable,
    /// otherwise sample data. A snapshot that exists but can't be decoded is
    /// backed up (never overwritten) before falling back, so real user data is
    /// recoverable instead of being silently replaced.
    @MainActor
    static var storedOrSample: AppStore {
        // Load the signed-in coach's partition (nil = guest / signed-out).
        let userID = UserDefaults.standard.string(forKey: "appleUserID")
        let persistence = UserDefaultsPersistenceService(namespace: userID)
        let snapshot = Self.loadSnapshot(from: persistence)

        // The CI build is unsigned and carries no iCloud entitlement, so
        // touching CKContainer (account status on launch) traps the app before
        // it can bootstrap. This bites both the UI-tested app (launched with
        // -uiTesting) and the unit-test host (the app's @main runs to host the
        // XCTest bundle). Skip CloudKit in either test context; normal runs are
        // unaffected, and the pure sync mapping is covered by SyncRecords tests.
        let cloudKit = AppEnvironment.isTestingOrUITesting ? nil : CloudKitSyncService(namespace: userID)
        return AppStore(snapshot: snapshot, persistence: persistence, cloudKit: cloudKit)
    }

    private static func loadSnapshot(from persistence: PersistenceService) -> AppSnapshot {
        switch persistence.load() {
        case .success(let loaded) where !loaded.teams.isEmpty:
            return loaded
        case .success, .empty:
            // Decoded-but-empty or a coach we haven't seen: seed with sample data.
            return SampleData.snapshot
        case .corrupt(let data, let error):
            // Preserve the unreadable blob before any save can clobber it.
            persistence.backupCorruptData(data)
            assertionFailure("Could not decode persisted snapshot; backed up under the corrupt-backup key. \(error)")
            return SampleData.snapshot
        }
    }

    /// Switches which coach's data is active. Called when the signed-in Apple
    /// user changes: the outgoing coach's data is saved under their partition and
    /// the incoming coach's data (or a fresh sample) is loaded — so a different
    /// account never sees the previous coach's roster, and no one loses data.
    func switchUser(to userID: String?) {
        persistence.setNamespace(userID)
        restore(Self.loadSnapshot(from: persistence), adoptVersion: true)
        lastSyncedRecords = SyncRecords.records(from: snapshot)
        cloudKit?.setNamespace(userID)
    }

    /// Synchronously flushes any pending background write. Call when the app is
    /// about to suspend so the latest state is durable before termination.
    func flushPendingWrites() {
        persistence.flushPendingSync()
    }

    // MARK: - Derived collections

    var selectedTeam: Team {
        teams.first(where: { $0.id == selectedTeamID }) ?? teams[0]
    }

    var roster: [Player] { players(inTeam: selectedTeamID) }

    var teamSessions: [TrainingSession] { sessions(inTeam: selectedTeamID) }

    var nextSession: TrainingSession? { nextSession(inTeam: selectedTeamID) }

    var teamGames: [GameEvent] { games(inTeam: selectedTeamID) }

    var nextGame: GameEvent? { nextGame(inTeam: selectedTeamID) }

    // MARK: - Sample data

    func resetToSampleData() {
        restore(SampleData.snapshot)
    }

    // MARK: - Persistence

    /// When true, `persist()` is deferred so a multi-collection mutation writes
    /// a single, consistent snapshot instead of several half-updated ones.
    private var isBatchingPersist = false

    /// Groups several mutations into one persisted snapshot. Nested calls are
    /// safe; only the outermost `batch` triggers the final write.
    func batch(_ work: () -> Void) {
        let wasBatching = isBatchingPersist
        isBatchingPersist = true
        // defer guarantees the flag is restored and the batched write happens
        // even if `work` ever starts throwing — never leaving persistence
        // permanently suppressed.
        defer {
            isBatchingPersist = wasBatching
            if !wasBatching { persist() }
        }
        work()
    }

    /// Monotonic edit counter for iCloud conflict resolution (newest-wins).
    private var dataVersion = 0
    /// When set, the next persist adopts this version instead of bumping — used
    /// when loading a remote/other-user snapshot rather than making a local edit.
    private var adoptingVersion: Int?

    private var snapshot: AppSnapshot {
        AppSnapshot(
            teams: teams,
            players: players,
            drills: drills,
            sessions: sessions,
            diagrams: diagrams,
            games: games,
            events: events,
            selectedTeamID: selectedTeamID,
            memberships: memberships,
            people: people,
            userAccounts: userAccounts,
            organizations: organizations,
            orgMemberships: orgMemberships,
            formTemplates: formTemplates,
            formInstances: formInstances,
            dataVersion: dataVersion
        )
    }

    private func persist() {
        guard !isBatchingPersist else { return }
        // A local edit bumps the version; adopting a remote/other-user snapshot
        // keeps its version so it isn't mistaken for a newer local change.
        if let adopted = adoptingVersion {
            dataVersion = adopted
            adoptingVersion = nil
        } else {
            dataVersion += 1
        }
        persistence.save(snapshot)
        publishWidgetData()
        syncLocalChanges()
        // Reschedule reminders only when the schedule itself changed (and once
        // per batch), not on every attendance/score mutation.
        if remindersDirty {
            remindersDirty = false
            if eventRemindersEnabled { refreshEventReminders() }
        }
        // Invalidate a pending undo once a *subsequent* change lands.
        if undoJustRegistered {
            undoJustRegistered = false
        } else if undoMessage != nil {
            dismissUndo()
        }
    }

    /// Publishes the soonest fixture (across all teams) to the app group and
    /// reloads the Home Screen widget — but only when it actually changed, so
    /// frequent saves don't thrash WidgetKit.
    func publishWidgetData() {
        let fixture: FixtureSnapshot? = soonestGame.map { game in
            let team = teams.first { $0.id == game.teamID }
            return FixtureSnapshot(
                teamName: team?.name ?? "",
                opponent: game.opponent,
                date: game.date,
                location: game.location,
                isHome: game.isHome,
                accentHex: team?.accent.hex ?? "4F46E5"
            )
        }
        guard fixture != WidgetSharedStore.load() else { return }
        WidgetSharedStore.save(fixture)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Backup & restore

    /// Encodes the entire app state as pretty-printed JSON for export/sharing.
    func exportData() -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(snapshot)
    }

    /// Replaces all state from an exported backup. Returns false (leaving the
    /// current state untouched) if the data isn't a valid, non-empty snapshot.
    @discardableResult
    func importData(_ data: Data) -> Bool {
        guard let imported = try? JSONDecoder().decode(AppSnapshot.self, from: data),
              !imported.teams.isEmpty else { return false }
        restore(imported)
        return true
    }

    /// Replaces all state with `snapshot`. `adoptVersion` keeps the snapshot's
    /// own `dataVersion` (loading remote/other-user data); the default bumps the
    /// version (a local replacement like import/reset/onboarding, which should
    /// win over older remote data).
    private func restore(_ snapshot: AppSnapshot, adoptVersion: Bool = false) {
        // restore starts its own batch; calling it mid-batch would defer the
        // consuming persist and let `adoptingVersion` leak into a later edit.
        assert(!isBatchingPersist, "restore must not be called within a batch")
        if adoptVersion { adoptingVersion = snapshot.dataVersion }
        batch {
            teams = snapshot.teams
            players = snapshot.players
            drills = snapshot.drills
            sessions = snapshot.sessions
            diagrams = snapshot.diagrams
            games = snapshot.games
            events = snapshot.events
            memberships = snapshot.memberships
            people = snapshot.people
            userAccounts = snapshot.userAccounts
            organizations = snapshot.organizations
            orgMemberships = snapshot.orgMemberships
            formTemplates = snapshot.formTemplates
            formInstances = snapshot.formInstances
            selectedTeamID = teams.contains(where: { $0.id == snapshot.selectedTeamID })
                ? snapshot.selectedTeamID
                : (teams.first?.id ?? snapshot.selectedTeamID)
        }
    }

    // MARK: - Onboarding

    /// Replaces all data with a single freshly-created team. Used by onboarding
    /// when a coach chooses to start clean instead of exploring the sample data.
    func startFresh(name: String, ageGroup: AgeGroup, season: String, accent: TeamAccent) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let team = Team(
            id: UUID(),
            name: trimmed.isEmpty ? "My Team" : trimmed,
            ageGroup: ageGroup,
            season: season,
            accentName: accent.rawValue,
            trainingDefaults: .standard
        )
        restore(AppSnapshot(teams: [team], players: [], drills: [], sessions: [],
                            diagrams: [], games: [], events: [], selectedTeamID: team.id))
    }

    // MARK: - Undo

    /// A short-lived message shown after a delete; `nil` when there's nothing to
    /// undo. The captured snapshot lets any delete (including cascading team
    /// deletes) be reverted as a whole.
    @Published private(set) var undoMessage: String?
    private var undoSnapshot: AppSnapshot?
    /// True for the single persist caused by the delete itself, so a *later*
    /// change can invalidate the undo offer (undo restores a whole snapshot, so
    /// undoing after an unrelated edit would silently revert that edit too).
    private var undoJustRegistered = false

    /// Snapshots the current state so the next delete can be reverted. Call
    /// *before* the mutation so the removed items are still captured.
    func registerUndo(_ message: String) {
        undoSnapshot = snapshot
        undoMessage = message
        undoJustRegistered = true
    }

    /// Restores the state captured before the most recent delete.
    func undoLastDelete() {
        guard let undoSnapshot else { return }
        restore(undoSnapshot)
        self.undoSnapshot = nil
        undoMessage = nil
    }

    func dismissUndo() {
        undoSnapshot = nil
        undoMessage = nil
    }

    var hasCorruptBackup: Bool { persistence.corruptBackup() != nil }
    func corruptBackupData() -> Data? { persistence.corruptBackup() }
    func clearCorruptBackup() { persistence.clearCorruptBackup() }
}

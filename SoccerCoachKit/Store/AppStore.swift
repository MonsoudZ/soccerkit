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
    /// Polymorphic, scoped sharing grants.
    @Published var shareGrants: [ShareGrant] {
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
    /// The remote sync backend — CloudKit today, the Go API once configured.
    /// Both satisfy `RemoteSyncService`, so the store code is transport-agnostic.
    private let remoteSync: RemoteSyncService?
    /// Fingerprints of the records the remote is known to have, so each persist
    /// pushes only what changed. Loaded at launch and written back on suspend:
    /// rebuilding it from local data every launch declared everything already
    /// synced, which quietly dropped any edit made while the remote was
    /// unreachable.
    private var syncedDigests: [SyncRecordKey: String] = [:]
    /// Which coach's baseline is loaded (nil = guest), so a user switch swaps it.
    private var syncNamespace: String?
    private var watermark: SyncWatermarkStore { SyncWatermarkStore(namespace: syncNamespace) }
    /// True while applying a remote change, so it isn't re-uploaded.
    private var isApplyingRemote = false
    /// True while `switchUser` swaps partitions, so the persist that the swap
    /// itself triggers can't push. See `syncLocalChanges`.
    private var isSwitchingUser = false

    /// Whether iCloud (CloudKit) sync is on, so the coach's data follows them
    /// across devices with record-level merge.
    @Published var cloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cloudSyncEnabled, forKey: "iCloudSyncEnabled")
            if cloudSyncEnabled {
                remoteSync?.start()
                syncLocalChanges()
            } else {
                remoteSync?.stop()
                syncStatus = .off
            }
        }
    }

    /// Where CloudKit sync stands, surfaced in Settings so sync isn't silent.
    @Published private(set) var syncStatus: SyncStatus = .off

    /// Whether changes are reaching disk. A save that can't be sealed is dropped
    /// rather than written in the clear (see `SnapshotCipher`), and this is what
    /// stops that being invisible to the coach it happens to.
    @Published private(set) var saveStatus: SaveStatus = .saved

    /// Re-attempts sync after a failure or once an iCloud account is available.
    func retrySync() {
        guard cloudSyncEnabled else { return }
        remoteSync?.start()
    }

    /// How long a pull-to-refresh spinner is allowed to run before it gives up
    /// waiting. The fetch itself carries on; this only caps how long the coach
    /// is asked to watch a request that may never answer.
    private static let refreshSpinnerCap: Duration = .seconds(20)

    /// Fetches remote changes and waits for the attempt to settle.
    ///
    /// Called when the app returns to the foreground, so the other device's
    /// edits are there when the coach looks — sync used to pull once at launch
    /// and then wait for the next one — and by pull-to-refresh.
    ///
    /// Awaitable because `.refreshable` holds its spinner exactly as long as
    /// this call: returning early would drop the spinner the instant the gesture
    /// ended, which reads as "refreshed, nothing new" no matter what the network
    /// was actually doing.
    ///
    /// A refresh with sync off, or on a build with no remote configured, returns
    /// without reaching for anything. There is nothing to fetch, and a coach who
    /// turned sync off shouldn't have a gesture quietly turn it back on.
    func refreshFromRemote() async {
        guard cloudSyncEnabled, let remoteSync else { return }
        await withCheckedContinuation { continuation in
            let gate = RefreshGate(continuation)
            // Armed before the call: `refresh` may run its completion
            // synchronously (a stopped service does), and the gate has to be
            // able to cancel a cap that is already in place.
            gate.cap = Task {
                try? await Task.sleep(for: Self.refreshSpinnerCap)
                guard !Task.isCancelled else { return }
                gate.finish()
            }
            remoteSync.refresh { gate.finish() }
        }
    }

    /// Built in `init` rather than as a property default: `ScheduleNotifier` is
    /// `@MainActor`, and a property default expression is a nonisolated context
    /// in the Swift 5 language mode.
    private let scheduleNotifier: ScheduleNotifier

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
    /// Built in `init` rather than as a default value: a property default
    /// expression is a nonisolated context in the Swift 5 language mode, so it
    /// can't call the `@MainActor` view model's initializer.
    let gameDay: GameDayViewModel

    init(snapshot: AppSnapshot,
         persistence: PersistenceService = UserDefaultsPersistenceService(),
         remoteSync: RemoteSyncService? = nil,
         namespace: String? = nil,
         gameDaySessions: GameDaySessionStore? = nil) {
        let resolvedTeams = Self.atLeastOneTeam(snapshot.teams)
        self.teams = resolvedTeams
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
        self.shareGrants = snapshot.shareGrants
        self.formTemplates = snapshot.formTemplates
        self.formInstances = snapshot.formInstances
        self.selectedTeamID = resolvedTeams.contains(where: { $0.id == snapshot.selectedTeamID }) ? snapshot.selectedTeamID : (resolvedTeams.first?.id ?? snapshot.selectedTeamID)
        self.dataVersion = snapshot.dataVersion
        self.persistence = persistence
        self.remoteSync = remoteSync
        self.cloudSyncEnabled = (UserDefaults.standard.object(forKey: "iCloudSyncEnabled") as? Bool) ?? (remoteSync != nil)
        self.eventRemindersEnabled = UserDefaults.standard.bool(forKey: "eventRemindersEnabled")
        self.reminderLeadMinutes = (UserDefaults.standard.object(forKey: "reminderLeadMinutes") as? Int) ?? 60
        self.syncNamespace = namespace
        // Fall back to the current snapshot when there's no stored baseline: the
        // services' one-time bootstrap owns the initial full upload, so an
        // upgrade shouldn't re-push the whole season just because this is the
        // first launch that keeps a watermark.
        self.syncedDigests = SyncWatermarkStore(namespace: namespace).load()
            ?? SyncRecords.digests(from: SyncRecords.records(from: snapshot))
        // A live match is saved per coach, so it can't be read by another
        // account on the device. Skipped under test unless a store is injected,
        // so a test's view model doesn't write into the real defaults.
        self.scheduleNotifier = ScheduleNotifier()
        self.gameDay = GameDayViewModel(sessionStore: gameDaySessions
            ?? (AppEnvironment.isTestingOrUITesting ? nil : UserDefaultsGameDaySessionStore(namespace: namespace)))
        // After every stored property: this captures self. Writes happen on a
        // background queue, so the outcome arrives off the main actor and hops
        // here before it touches published state.
        persistence.onWriteOutcome = { [weak self] saved in
            Task { @MainActor in self?.saveStatus = saved ? .saved : .unsaved }
        }
        publishWidgetData()
        if let remoteSync {
            remoteSync.snapshotProvider = { [weak self] in self?.snapshot ?? snapshot }
            remoteSync.applyRemoteChanges = { [weak self] upserts, deletes in
                self?.applyRemoteChanges(upserts: upserts, deletes: deletes)
            }
            remoteSync.onStatusChange = { [weak self] status in
                self?.syncStatus = status
            }
            if cloudSyncEnabled { remoteSync.start() }
        }
    }

    /// Applies record-level changes fetched from the remote, without re-uploading
    /// them — but without claiming the remote has anything it didn't send.
    ///
    /// Applying a remote change can make the store change something of its own.
    /// `restore` runs `atLeastOneTeam`, which invents a recovery team when a
    /// remote delete empties `teams`, and re-points `selectedTeamID` when the
    /// stored one no longer exists. Those are local edits that happen to occur
    /// inside a remote apply, and the remote has never seen them.
    ///
    /// The baseline used to be taken wholesale from the resulting snapshot, which
    /// fingerprinted those inventions as already-synced. They then dropped out of
    /// every later diff and were never pushed — not on the next edit, not on
    /// relaunch, ever — so two devices that both lost their last team each
    /// recovered into a private team of their own and never converged. Adopting
    /// only the keys the remote actually sent leaves anything the store invented
    /// with no baseline entry, so the very next diff picks it up.
    private func applyRemoteChanges(upserts: [SyncRecord], deletes: [SyncRecordKey]) {
        var updated = snapshot
        for record in upserts { SyncRecords.apply(record, to: &updated) }
        for key in deletes { SyncRecords.delete(type: key.type, id: key.id, from: &updated) }
        isApplyingRemote = true
        restore(updated, adoptVersion: true)
        isApplyingRemote = false

        adoptBaseline(forRemote: upserts, deletes: deletes)
        // Now that the baseline names only what the remote holds, push whatever
        // the repair above invented. Without this it would wait for the coach's
        // next edit to go up.
        syncLocalChanges()
    }

    /// Moves the sync baseline over exactly the records the remote sent, leaving
    /// every other entry — and every absence — as it was.
    ///
    /// Digests come from the resulting snapshot rather than from the received
    /// payloads, so a record still can't be echoed back even if the bytes we
    /// re-encode differ from the bytes we were handed.
    private func adoptBaseline(forRemote upserts: [SyncRecord], deletes: [SyncRecordKey]) {
        let current = SyncRecords.digests(from: SyncRecords.records(from: snapshot))
        var baseline = syncedDigests
        for key in deletes { baseline.removeValue(forKey: key) }
        for record in upserts {
            let key = SyncRecordKey(record.type, record.id)
            // Absent from `current` means applying it didn't land a record we can
            // re-encode; drop the entry rather than assert a digest we don't have.
            baseline[key] = current[key]
        }
        syncedDigests = baseline
    }

    /// Monotonic tag for in-flight pushes, so a late completion can't move the
    /// sync baseline backward past a newer push that already advanced it.
    private var pushGeneration = 0

    /// Pushes local record changes to the remote (diffed against the last sync).
    private func syncLocalChanges() {
        guard let remoteSync, cloudSyncEnabled else { return }

        // Every baseline change — here or in an in-flight push's completion —
        // supersedes older ones, so a late completion can't move the baseline
        // backward past newer state. Bumped before the guards below so a push
        // still in flight for the outgoing coach can't land after a user switch
        // and drag the incoming coach's baseline back to it.
        pushGeneration += 1
        let generation = pushGeneration

        // A partition swap is not a local edit, and must not push: the snapshot
        // being written belongs to the incoming coach while `remoteSync` still
        // points at the outgoing coach's namespace. Diffing here uploaded one
        // coach's season into the other's zone — and, because none of the
        // outgoing coach's records appear in the incoming snapshot, tombstoned
        // every one of them. `switchUser` sets the baseline itself once both
        // sides point at the new namespace.
        guard !isSwitchingUser else { return }

        // Nothing may push while a remote change is being applied: `restore`
        // fires a `persist()` mid-apply, and the baseline still describes the
        // pre-apply world, so diffing here would push the remote's own changes
        // straight back at it. `applyRemoteChanges` moves the baseline and calls
        // this again itself, once the apply is complete.
        guard !isApplyingRemote else { return }

        let current = SyncRecords.records(from: snapshot)

        let (upserts, deletes) = SyncRecords.diff(fromDigests: syncedDigests, to: current)
        guard !upserts.isEmpty || !deletes.isEmpty else {
            syncedDigests = SyncRecords.digests(from: current)
            return
        }

        // Advance the baseline only once the push actually lands. This used to run
        // in a `defer` — before the fire-and-forget push had even started — so a
        // push that failed (dropped connection, 401, or the server's owner-scope
        // 403) was erased from the next diff and lost for good. Leaving the
        // baseline put on failure means the records reappear in the next diff and
        // retry on the next local edit.
        remoteSync.push(upserts: upserts, deletes: deletes) { [weak self] landed in
            guard let self, landed, generation == self.pushGeneration else { return }
            self.syncedDigests = SyncRecords.digests(from: current)
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

        return AppStore(snapshot: snapshot, persistence: persistence,
                        remoteSync: Self.makeRemoteSync(namespace: userID),
                        namespace: userID)
    }

    /// Chooses the sync transport at launch:
    /// - No sync at all under test (the unsigned CI build has no iCloud
    ///   entitlement, and touching CKContainer traps the app on launch — this
    ///   bites both the UI-tested app and the unit-test host).
    /// - The Go backend (`APISyncService`) when `BackendBaseURL` is configured.
    /// - CloudKit otherwise — the shipping default until the backend is set.
    @MainActor
    private static func makeRemoteSync(namespace: String?) -> RemoteSyncService? {
        guard !AppEnvironment.isTestingOrUITesting else { return nil }
        if BackendConfig.isConfigured {
            let tokens = TokenStore()
            if let client = APIClient(tokenProvider: { tokens.token }) {
                return APISyncService(client: client, namespace: namespace, tokenStore: tokens)
            }
        }
        return CloudKitSyncService(namespace: namespace)
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
        watermark.save(syncedDigests) // bank the outgoing coach's baseline

        // Nothing in here may push. `restore` fires a `persist()`, and for the
        // length of the swap that persist would diff the outgoing coach's
        // baseline against the incoming coach's snapshot and hand the result to a
        // `remoteSync` still pointed at the outgoing coach's namespace — writing
        // one coach's season into the other's zone and tombstoning the outgoing
        // coach's records along the way. The baseline is set explicitly below
        // instead, once every side names the new partition.
        isSwitchingUser = true
        defer { isSwitchingUser = false }

        persistence.setNamespace(userID)
        syncNamespace = userID
        restore(Self.loadSnapshot(from: persistence), adoptVersion: true)
        syncedDigests = watermark.load()
            ?? SyncRecords.digests(from: SyncRecords.records(from: snapshot))
        // Last, and after `restore`: both services re-point asynchronously and
        // read `snapshotProvider` when they do, so the incoming snapshot has to
        // be loaded before they look.
        remoteSync?.setNamespace(userID)
        // The live match is partitioned too — the outgoing coach's stays saved
        // under their own key rather than following them out.
        gameDay.switchSessionStore(AppEnvironment.isTestingOrUITesting
            ? nil : UserDefaultsGameDaySessionStore(namespace: userID))
    }

    /// Completes the Sign in with Apple → backend handshake: exchanges the fresh
    /// Apple identity token for a backend session token (persisted in
    /// `TokenStore`), then (re)starts sync so the first pull carries it.
    ///
    /// No-op unless the Go backend is configured (`BackendBaseURL`) — CloudKit
    /// builds never call the API. Only a live sign-in produces an identity token;
    /// a returning coach already has a stored session token, so this isn't needed
    /// on relaunch. Failures surface via `syncStatus` (the coach can retry).
    func authenticateBackend(identityToken: String?, authorizationCode: String?, fullName: String?) {
        guard BackendConfig.isConfigured,
              let identityToken, !identityToken.isEmpty,
              let client = APIClient(tokenProvider: { TokenStore().token })
        else { return }

        let request = AppleAuthRequest(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            fullName: fullName
        )
        Task {
            // The identity token is short-lived and produced once, so a transient
            // failure (e.g. a loopback blip as the Sign in with Apple sheet tears
            // down) must not lose the sign-in. Retry transport errors with a short
            // backoff before giving up; auth/HTTP failures are terminal.
            let maxAttempts = 4
            for attempt in 1...maxAttempts {
                do {
                    let response = try await client.authenticateApple(request)
                    // Persist the refresh token alongside the access token, so an
                    // expired access token rotates instead of forcing another Sign
                    // in with Apple. If the keychain won't take them, say so: a
                    // session that didn't save is not a session, and starting sync
                    // on it would loop the coach through "sign in again" forever.
                    guard TokenStore().save(token: response.token,
                                            refreshToken: response.refreshToken) else {
                        syncStatus = .failed("Couldn't save your session")
                        return
                    }
                    // Authenticated now — (re)start sync so its pull carries the token.
                    if cloudSyncEnabled { remoteSync?.start() }
                    return
                } catch let error as APIError {
                    if case .transport = error, attempt < maxAttempts {
                        try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                        continue
                    }
                    syncStatus = .failed(error.userMessage)
                    return
                } catch {
                    syncStatus = .failed("Couldn't sign in to sync")
                    return
                }
            }
        }
    }

    /// Synchronously flushes any pending background write. Call when the app is
    /// about to suspend so the latest state is durable before termination.
    func flushPendingWrites() {
        persistence.flushPendingSync()
        // The sync baseline rides along: this runs when the app leaves the
        // foreground, which is when a termination realistically follows. Writing
        // it here rather than on every push keeps a large map off the hot path.
        watermark.save(syncedDigests)
    }

    // MARK: - Derived collections

    /// The current team. `teams[0]` is a safe fallback because `teams` is never
    /// empty — every path that assigns it goes through `atLeastOneTeam`, and
    /// `deleteTeam` won't remove the last one.
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
            shareGrants: shareGrants,
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

    /// Permanently deletes the account: the remote data (the CloudKit zone, or
    /// the server account via `DELETE /me`), then the on-device partition and the
    /// session tokens. Returns `false` — leaving local data untouched — if the
    /// remote deletion fails, so the app never claims an account was deleted while
    /// its server data survives. The caller signs the user out on success (which
    /// reloads a clean guest namespace); no local mutation must happen in between,
    /// or `persist()` would resurrect the just-purged partition.
    func deleteAccount() async -> Bool {
        if let remoteSync {
            let purged = await withCheckedContinuation { continuation in
                remoteSync.purge { continuation.resume(returning: $0) }
            }
            guard purged else { return false }
        }
        TokenStore().clear()
        persistence.purge()
        gameDay.discardSavedSession()
        // The remote's copy is gone, so nothing can be assumed synced against it.
        watermark.clear()
        syncedDigests = [:]
        return true
    }

    /// Replaces all state with `snapshot`. `adoptVersion` keeps the snapshot's
    /// own `dataVersion` (loading remote/other-user data); the default bumps the
    /// version (a local replacement like import/reset/onboarding, which should
    /// win over older remote data).
    /// The app assumes there is always a current team: `selectedTeam` is
    /// non-optional and read throughout the UI. Locally that holds — `deleteTeam`
    /// refuses to remove the last team (`canDeleteTeam`) — but a remote sync can
    /// still empty `teams` when two devices hold different sets: this device has
    /// only team X, another device (which also has Y, so its delete is allowed)
    /// deletes X, and the tombstone syncs here. Rather than let `teams` go empty
    /// and trap the next `selectedTeam` read, recover into a valid state.
    private static func atLeastOneTeam(_ teams: [Team]) -> [Team] {
        teams.isEmpty ? [recoveryTeam()] : teams
    }

    private static func recoveryTeam() -> Team {
        Team(id: UUID(), name: "My Team", ageGroup: .u10,
             season: "\(Calendar.current.component(.year, from: Date()))",
             accentName: TeamAccent.teal.rawValue)
    }

    private func restore(_ snapshot: AppSnapshot, adoptVersion: Bool = false) {
        // restore starts its own batch; calling it mid-batch would defer the
        // consuming persist and let `adoptingVersion` leak into a later edit.
        assert(!isBatchingPersist, "restore must not be called within a batch")
        if adoptVersion { adoptingVersion = snapshot.dataVersion }
        batch {
            teams = Self.atLeastOneTeam(snapshot.teams)
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
            shareGrants = snapshot.shareGrants
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

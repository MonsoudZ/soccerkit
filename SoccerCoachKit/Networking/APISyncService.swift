import Foundation

/// The seam `AppStore` drives sync through. `CloudKitSyncService` and
/// `APISyncService` both implement it — the former against CloudKit, the latter
/// against the Go backend. `AppStore.makeRemoteSync` picks which one to build
/// (the API service when a backend is configured, else CloudKit); the store code
/// doesn't change, only which conformer it's handed.
@MainActor
protocol RemoteSyncService: AnyObject {
    /// Supplies the current full snapshot (for an initial bootstrap push).
    var snapshotProvider: (() -> AppSnapshot)? { get set }
    /// Applies records fetched from the remote into the store, without
    /// re-enqueuing them for upload.
    var applyRemoteChanges: ((_ upserts: [SyncRecord], _ deletes: [SyncRecordKey]) -> Void)? { get set }
    /// Reports sync lifecycle so the UI can surface status.
    var onStatusChange: ((SyncStatus) -> Void)? { get set }

    /// Begins syncing. The first `start()` for a namespace must also upload the
    /// snapshot already on the device (see `snapshotProvider`): `AppStore` seeds
    /// its diff baseline from local data, so without a bootstrap the first diff
    /// is empty and pre-existing data would never reach the remote at all.
    func start()
    /// Fetches whatever the remote has gained since the last cursor, without
    /// restarting sync. `start()` pulls once and then never again on its own, so
    /// without this a second device's changes only showed up at relaunch.
    func refresh()
    func stop()
    /// Pushes local changes to the remote. `completion(true)` means the batch was
    /// durably accepted (CloudKit) or acknowledged by the server (API); the caller
    /// advances its sync baseline only then. `completion(false)` means the batch
    /// did not land, so the caller keeps the records for the next diff.
    func push(upserts: [SyncRecord], deletes: [SyncRecordKey], completion: @escaping (Bool) -> Void)
    func setNamespace(_ namespace: String?)
    /// Permanently deletes this account's remote data (the CloudKit zone, or the
    /// server account via `DELETE /me`). `completion(true)` only when the remote
    /// confirms; on `false` the caller must not claim the account was deleted.
    func purge(completion: @escaping (Bool) -> Void)
}

/// Syncs the store against the Go backend's `/v1/sync` delta endpoint. Pushes
/// are the diffs `AppStore` already computes via `SyncRecords.diff`; pulls apply
/// the server delta since the last cursor. Best-effort and non-blocking — every
/// call spawns a `Task` and reports through `onStatusChange`, mirroring
/// `CloudKitSyncService`.
@MainActor
final class APISyncService: RemoteSyncService {
    var snapshotProvider: (() -> AppSnapshot)?
    var applyRemoteChanges: ((_ upserts: [SyncRecord], _ deletes: [SyncRecordKey]) -> Void)?
    var onStatusChange: ((SyncStatus) -> Void)?

    private let client: APIClient
    private var namespace: String
    private var isRunning = false
    private let defaults: UserDefaults
    private let tokenStore: TokenStore
    /// The single in-flight refresh, so two calls that 401 at once share one
    /// rotation instead of racing (a rotating endpoint would reject the loser).
    private var refreshInFlight: Task<Bool, Never>?
    private var cursorKey: String { "apiSyncCursor.\(namespace)" }
    /// Whether this namespace's existing data has been uploaded at least once.
    /// Durable, so the whole season isn't re-pushed on every launch.
    private var bootstrapKey: String { "apiSyncBootstrapped.\(namespace)" }

    init(client: APIClient, namespace: String?, defaults: UserDefaults = .standard,
         tokenStore: TokenStore = TokenStore()) {
        self.client = client
        self.namespace = namespace ?? "default"
        self.defaults = defaults
        self.tokenStore = tokenStore
    }

    func start() {
        isRunning = true
        onStatusChange?(.syncing)
        Task {
            await pull()
            await bootstrapIfNeeded()
        }
    }

    /// Pulls again on demand — the app calls this when it returns to the
    /// foreground, which is when a coach expects to see what their other device
    /// did. No-op while stopped: there is no session to pull with.
    func refresh() {
        guard isRunning else { return }
        Task { await pull() }
    }

    func stop() {
        isRunning = false
        onStatusChange?(.off)
    }

    func setNamespace(_ namespace: String?) {
        let ns = namespace ?? "default"
        guard ns != self.namespace else { return }
        self.namespace = ns
        if isRunning {
            Task {
                await pull()
                await bootstrapIfNeeded() // the new namespace has its own flag
            }
        }
    }

    func push(upserts: [SyncRecord], deletes: [SyncRecordKey], completion: @escaping (Bool) -> Void) {
        guard isRunning else { completion(false); return }
        Task {
            let ok = await performPush(upserts: upserts, deletes: deletes)
            completion(ok)
        }
    }

    func purge(completion: @escaping (Bool) -> Void) {
        Task {
            do {
                try await client.deleteAccount()
                tokenStore.clear()
                defaults.removeObject(forKey: cursorKey)
                // The account's server data is gone, so a later sync must upload
                // from scratch rather than trust the old bootstrap.
                defaults.removeObject(forKey: bootstrapKey)
                isRunning = false
                completion(true)
            } catch {
                onStatusChange?(.failed(Self.message(for: error)))
                completion(false)
            }
        }
    }

    // MARK: - Bootstrap

    /// Uploads everything already on the device, once per namespace.
    ///
    /// `AppStore` pushes only `SyncRecords.diff(from: lastSyncedRecords, …)`, and
    /// it seeds that baseline from the local snapshot at launch — so the first
    /// diff is empty by construction and a coach's existing season would never be
    /// uploaded, on this device or visible on any other. The bootstrap is that
    /// missing first push: the full record set, diffed against nothing.
    ///
    /// Runs after the initial pull so anything the server already holds is merged
    /// in first and goes up in the same batch, rather than being overwritten by a
    /// stale local copy. The flag advances only on a server ack, so a bootstrap
    /// that fails is retried on the next `start()`.
    private func bootstrapIfNeeded() async {
        guard isRunning, !defaults.bool(forKey: bootstrapKey),
              let snapshot = snapshotProvider?() else { return }
        let records = SyncRecords.records(from: snapshot)
        guard !records.isEmpty else {
            defaults.set(true, forKey: bootstrapKey) // nothing to upload
            return
        }
        if await performPush(upserts: records, deletes: []) {
            defaults.set(true, forKey: bootstrapKey)
        }
    }

    // MARK: - Networking

    /// The most pages one pull will drain before giving up and leaving the rest to the
    /// next trigger. A stop is needed because the loop's exit condition is the server's
    /// cursor: a server that returned records without advancing it would otherwise spin
    /// forever. At the server's page size this is far more records than any coach has,
    /// so reaching it means something is wrong, not that someone is busy.
    private static let maxPullPages = 100

    /// Drains the delta rather than taking one response and calling it done.
    ///
    /// A pull returns everything past the cursor, and the server is free to answer with
    /// only part of it — it has to be, or a reinstall asking `since=0` makes it build the
    /// account's entire history in memory at once. The reply carries no "there is more"
    /// flag and does not need one: the cursor is the contract. If it advanced, ask again
    /// from where it now points; when it stops moving, the account is caught up.
    ///
    /// Without this loop a paged server would look like data loss. The records are not
    /// lost — the cursor is saved, so the next pull continues — but pulls only happen on
    /// launch and on foreground, so a coach reinstalling would watch their teams arrive a
    /// page per app switch with nothing explaining why.
    private func pull() async {
        do {
            for _ in 0..<Self.maxPullPages {
                let before = defaults.string(forKey: cursorKey)
                let response = try await withAuthRetry {
                    try await self.client.pull(since: self.defaults.string(forKey: self.cursorKey))
                }
                apply(response.records, deletes: response.deletes, cursor: response.cursor)

                if response.records.isEmpty && response.deletes.isEmpty { break }
                // The cursor standing still means this page told us nothing new, so
                // asking again would fetch the same rows forever.
                if defaults.string(forKey: cursorKey) == before { break }
            }
            onStatusChange?(.synced(Date()))
        } catch {
            onStatusChange?(.failed(Self.message(for: error)))
        }
    }

    /// Returns whether the batch was acknowledged by the server, so the caller can
    /// hold its sync baseline until a push actually lands.
    ///
    /// "Landed" means *every* record in the batch did. A record that fails wire
    /// encoding used to be dropped by a `compactMap` while the batch still
    /// reported success, so `AppStore` advanced its baseline past it and the
    /// record vanished from every later diff — silently unsynced, forever, with
    /// nothing surfaced. That is the same loss `36074ba` closed for failed
    /// pushes, reopened one line earlier in the encode.
    private func performPush(upserts: [SyncRecord], deletes: [SyncRecordKey]) async -> Bool {
        // Encode what we can and keep the good records moving, but remember that
        // the batch was incomplete.
        var encoded: [SyncRecordDTO] = []
        var droppedCount = 0
        for record in upserts {
            if let dto = try? SyncWireCodec.dto(from: record) {
                encoded.append(dto)
            } else {
                droppedCount += 1
                // The payload is JSON this app encoded itself, so failing to read
                // it back is a bug in our own encoding — assert so a regression is
                // visible rather than quietly costing a record. Exempt the test
                // host, which drives this path deliberately to prove the batch is
                // reported as *not* landed.
                if !AppEnvironment.isTestingOrUITesting {
                    assertionFailure("Could not encode \(record.type.rawValue) \(record.id) for the wire")
                }
            }
        }

        do {
            let request = SyncPushRequest(
                upserts: encoded,
                deletes: deletes.map(SyncWireCodec.keyDTO(from:)),
                cursor: defaults.string(forKey: cursorKey)
            )
            let response = try await withAuthRetry { try await self.client.push(request) }
            // Adopt any records the server won a conflict on.
            apply(response.conflicts, deletes: [], cursor: response.cursor)
            guard droppedCount == 0 else {
                // The server took the rest, but the baseline must not advance:
                // holding it keeps the dropped records in the next diff so they're
                // retried instead of lost.
                onStatusChange?(.failed("Couldn't sync \(droppedCount) item\(droppedCount == 1 ? "" : "s")"))
                return false
            }
            onStatusChange?(.synced(Date()))
            return true
        } catch {
            onStatusChange?(.failed(Self.message(for: error)))
            return false
        }
    }

    // MARK: - Session refresh

    /// Runs an authenticated call, and if it 401s, rotates the access token with
    /// the stored refresh token and retries once. Before this, an expired JWT
    /// dead-ended sync until the coach signed in with Apple again; the server
    /// issues a refresh token precisely so that isn't necessary.
    private func withAuthRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch APIError.unauthorized {
            guard await refreshSession() else { throw APIError.unauthorized }
            return try await operation() // retry once; the client reads the new token
        }
    }

    /// Rotates the session, coalescing concurrent callers onto one refresh.
    /// Returns whether a usable access token is now stored. A refresh the server
    /// rejects clears the tokens, so the next call fails fast to "sign in again"
    /// rather than looping on a dead token.
    private func refreshSession() async -> Bool {
        if let existing = refreshInFlight { return await existing.value }
        let task = Task { () -> Bool in
            defer { refreshInFlight = nil }
            guard let presented = tokenStore.refreshToken else { return false }
            do {
                let rotated = try await client.refresh(presented)
                // The session can end while a rotation is in flight, and this
                // `await` is a whole network round-trip wide. Signing out clears
                // the tokens; writing the rotated pair afterwards would put a
                // live session for the coach who just signed out back into the
                // keychain — precisely the leak `AuthController.signOut` clears
                // them to prevent, and enough for sync to keep talking to the
                // server as them. If what we presented is no longer what's
                // stored, the session moved on without us: drop the rotation.
                guard tokenStore.refreshToken == presented else { return false }
                // A rotation we can't persist is worse than no rotation: the
                // server has already revoked the token we presented, so a write
                // that silently failed would leave a dead refresh token on disk
                // and the retry below would replay the expired access token.
                // Report the refresh as failed instead of pretending it worked.
                guard tokenStore.save(token: rotated.accessToken,
                                      refreshToken: rotated.refreshToken) else { return false }
                return true
            } catch APIError.unauthorized {
                tokenStore.clear()
                return false
            } catch {
                // A transport/server blip isn't a dead session — keep the refresh
                // token so a later call can try again.
                return false
            }
        }
        refreshInFlight = task
        return await task.value
    }

    /// Decodes wire records/keys and hands them to the store; records of unknown
    /// types (a newer server) are skipped rather than fatal.
    private func apply(_ records: [SyncRecordDTO], deletes: [SyncKeyDTO], cursor: String?) {
        var upserts: [SyncRecord] = []
        for dto in records {
            // record(from:) throws and returns nil for unknown types; `try?`
            // flattens both to a single optional, so one bind takes the good ones.
            if let decoded = try? SyncWireCodec.record(from: dto) {
                upserts.append(decoded)
            }
        }
        let removals = deletes.compactMap(SyncWireCodec.key(from:))
        if !upserts.isEmpty || !removals.isEmpty {
            applyRemoteChanges?(upserts, removals)
        }
        if let cursor { defaults.set(cursor, forKey: cursorKey) }
    }

    private static func message(for error: Error) -> String {
        (error as? APIError)?.userMessage ?? "Sync error"
    }
}

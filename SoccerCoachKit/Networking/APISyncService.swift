import Foundation

/// The seam `AppStore` drives sync through. `CloudKitSyncService` already
/// implements this exact shape today; `APISyncService` implements it against the
/// Go backend. When the backend is live, `storedOrSample` chooses which one to
/// build (see the integration note at the bottom of this file) — the store code
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

    func start()
    func stop()
    /// Pushes local changes to the remote. `completion(true)` means the batch was
    /// durably accepted (CloudKit) or acknowledged by the server (API); the caller
    /// advances its sync baseline only then. `completion(false)` means the batch
    /// did not land, so the caller keeps the records for the next diff.
    func push(upserts: [SyncRecord], deletes: [SyncRecordKey], completion: @escaping (Bool) -> Void)
    func setNamespace(_ namespace: String?)
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
        if isRunning { Task { await pull() } }
    }

    func push(upserts: [SyncRecord], deletes: [SyncRecordKey], completion: @escaping (Bool) -> Void) {
        guard isRunning else { completion(false); return }
        Task {
            let ok = await performPush(upserts: upserts, deletes: deletes)
            completion(ok)
        }
    }

    // MARK: - Networking

    private func pull() async {
        do {
            let response = try await withAuthRetry {
                try await self.client.pull(since: self.defaults.string(forKey: self.cursorKey))
            }
            apply(response.records, deletes: response.deletes, cursor: response.cursor)
            onStatusChange?(.synced(Date()))
        } catch {
            onStatusChange?(.failed(Self.message(for: error)))
        }
    }

    /// Returns whether the batch was acknowledged by the server, so the caller can
    /// hold its sync baseline until a push actually lands.
    private func performPush(upserts: [SyncRecord], deletes: [SyncRecordKey]) async -> Bool {
        do {
            let request = SyncPushRequest(
                upserts: upserts.compactMap { try? SyncWireCodec.dto(from: $0) },
                deletes: deletes.map(SyncWireCodec.keyDTO(from:)),
                cursor: defaults.string(forKey: cursorKey)
            )
            let response = try await withAuthRetry { try await self.client.push(request) }
            // Adopt any records the server won a conflict on.
            apply(response.conflicts, deletes: [], cursor: response.cursor)
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
            guard let refresh = tokenStore.refreshToken else { return false }
            do {
                let rotated = try await client.refresh(refresh)
                tokenStore.token = rotated.accessToken
                tokenStore.refreshToken = rotated.refreshToken
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

// MARK: - Integration note
//
// To activate against the backend, in `AppStore.storedOrSample` prefer an
// `APISyncService` when a backend is configured, falling back to CloudKit:
//
//     let remote: RemoteSyncService?
//     if BackendConfig.isConfigured {
//         let tokens = TokenStore()
//         if let client = APIClient(tokenProvider: { tokens.token }) {
//             remote = APISyncService(client: client, namespace: userID)
//         } else { remote = CloudKitSyncService(namespace: userID) }
//     } else {
//         remote = AppEnvironment.isTestingOrUITesting ? nil : CloudKitSyncService(namespace: userID)
//     }
//
// That requires `AppStore.init` to take a `RemoteSyncService?` instead of the
// concrete `CloudKitSyncService?` (and `CloudKitSyncService` to declare
// `: RemoteSyncService` — it already has every member). Left undone here so the
// working CloudKit path is untouched until there's a live server to test against.

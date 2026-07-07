import CloudKit
import Foundation

/// Record-level iCloud sync via `CKSyncEngine`. Each entity is its own CloudKit
/// record in a per-coach private-database zone, so two devices editing different
/// records merge instead of overwriting a whole-document blob. Conflicts on the
/// same record resolve server-wins.
///
/// Runtime behaviour requires a signed build + iCloud account + the CloudKit
/// container and must be validated on-device; the pure record mapping lives in
/// `SyncRecords` and is unit-tested.
@available(iOS 17.0, *)
@MainActor
final class CloudKitSyncService: CKSyncEngineDelegate {
    private let container: CKContainer
    private var zoneID: CKRecordZone.ID
    private var namespace: String
    private var stateKey: String
    private var engine: CKSyncEngine?

    /// Supplies the current data so records can be materialised on demand.
    var snapshotProvider: (() -> AppSnapshot)?
    /// Applies fetched upserts/deletions into the store in one batch (the store
    /// must suppress re-enqueuing while applying these).
    var applyRemoteChanges: ((_ upserts: [SyncRecord], _ deletes: [SyncRecordKey]) -> Void)?

    private let defaults = UserDefaults.standard

    init(namespace: String?, containerID: String = "iCloud.com.monsoudzanaty.SoccerCoachKit") {
        self.namespace = namespace ?? "default"
        self.container = CKContainer(identifier: containerID)
        self.zoneID = CKRecordZone.ID(zoneName: "coach-\(self.namespace)", ownerName: CKCurrentUserDefaultName)
        self.stateKey = "ckSyncState.\(self.namespace)"
    }

    func start() {
        // Only spin up the engine when there's a usable iCloud account. Without
        // this check CKSyncEngine retries relentlessly and floods the log with
        // "Not Authenticated" — the common case in the Simulator or when the
        // user isn't signed into iCloud. A later start() (next launch, or after
        // sign-in) picks it up.
        Task { [weak self] in
            guard let self else { return }
            let status = try? await self.container.accountStatus()
            guard status == .available else { return }
            self.startEngine()
        }
    }

    private func startEngine() {
        guard engine == nil else { return }
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase,
            stateSerialization: loadState(),
            delegate: self
        )
        let engine = CKSyncEngine(configuration)
        self.engine = engine
        // Make sure the zone exists before any record save.
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: zoneID))])
    }

    func stop() { engine = nil }

    /// Re-points sync at a different coach's zone (per-Apple-ID isolation).
    func setNamespace(_ namespace: String?) {
        let ns = namespace ?? "default"
        guard ns != self.namespace else { return }
        self.namespace = ns
        self.zoneID = CKRecordZone.ID(zoneName: "coach-\(ns)", ownerName: CKCurrentUserDefaultName)
        self.stateKey = "ckSyncState.\(ns)"
        if engine != nil {
            stop()
            start() // rebuild for the new zone
        }
    }

    /// Enqueues local changes computed by `SyncRecords.diff`.
    func push(upserts: [SyncRecord], deletes: [SyncRecordKey]) {
        guard let engine else { return }
        var changes: [CKSyncEngine.PendingRecordZoneChange] = []
        changes += upserts.map { .saveRecord(recordID($0.type, $0.id)) }
        changes += deletes.map { .deleteRecord(recordID($0.type, $0.id)) }
        engine.state.add(pendingRecordZoneChanges: changes)
    }

    // MARK: - CKSyncEngineDelegate

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            saveState(update.stateSerialization)

        case .fetchedRecordZoneChanges(let changes):
            let upserts = changes.modifications.compactMap { syncRecord(from: $0.record) }
            let deletes = changes.deletions.compactMap { deletion -> SyncRecordKey? in
                decode(deletion.recordID).map { SyncRecordKey($0.0, $0.1) }
            }
            if !upserts.isEmpty || !deletes.isEmpty {
                applyRemoteChanges?(upserts, deletes)
            }

        case .sentRecordZoneChanges(let sent):
            // Server-wins: adopt the server's version of any conflicted record.
            let serverWins = sent.failedRecordSaves.compactMap { failure in
                failure.error.serverRecord.flatMap { syncRecord(from: $0) }
            }
            if !serverWins.isEmpty { applyRemoteChanges?(serverWins, []) }

        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        let snapshot = snapshotProvider?()

        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            guard let snapshot,
                  let (type, id) = self.decode(recordID),
                  let record = SyncRecords.record(from: snapshot, type: type, id: id)
            else { return nil }
            let ckRecord = CKRecord(recordType: type.rawValue, recordID: recordID)
            ckRecord["payload"] = record.payload as CKRecordValue
            return ckRecord
        }
    }

    // MARK: - Record id encoding (type is carried in the record name)

    private func recordID(_ type: SyncRecordType, _ id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "\(type.rawValue)|\(id)", zoneID: zoneID)
    }

    private nonisolated func decode(_ recordID: CKRecord.ID) -> (SyncRecordType, String)? {
        let parts = recordID.recordName.split(separator: "|", maxSplits: 1)
        guard parts.count == 2, let type = SyncRecordType(rawValue: String(parts[0])) else { return nil }
        return (type, String(parts[1]))
    }

    private nonisolated func syncRecord(from ckRecord: CKRecord) -> SyncRecord? {
        guard let (type, id) = decode(ckRecord.recordID),
              let payload = ckRecord["payload"] as? Data else { return nil }
        return SyncRecord(type: type, id: id, payload: payload)
    }

    // MARK: - State persistence

    private func loadState() -> CKSyncEngine.State.Serialization? {
        guard let data = defaults.data(forKey: stateKey) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    private func saveState(_ serialization: CKSyncEngine.State.Serialization) {
        if let data = try? JSONEncoder().encode(serialization) {
            defaults.set(data, forKey: stateKey)
        }
    }
}

import CryptoKit
import Foundation

/// One CloudKit record type per entity, so two devices editing *different*
/// records (e.g. each adds a player) merge instead of clobbering a whole-document
/// blob.
enum SyncRecordType: String, CaseIterable {
    case team = "Team"
    case player = "Player"
    case drill = "Drill"
    case session = "Session"
    case diagram = "Diagram"
    case game = "Game"
    case event = "Event"
    case rosterMembership = "RosterMembership"
    case person = "Person"
    case userAccount = "UserAccount"
    case organization = "Organization"
    case orgMembership = "OrgMembership"
    case shareGrant = "ShareGrant"
    case formTemplate = "FormTemplate"
    case formInstance = "FormInstance"
    case prefs = "Prefs"
}

/// A single syncable record: its type, stable id (the entity UUID, or a fixed id
/// for the singleton prefs), and a Codable payload of the entity.
struct SyncRecord: Equatable {
    let type: SyncRecordType
    let id: String
    let payload: Data
}

struct SyncRecordKey: Hashable {
    let type: SyncRecordType
    let id: String
    init(_ type: SyncRecordType, _ id: String) { self.type = type; self.id = id }
}

/// Pure conversion between an `AppSnapshot` and per-entity records, plus a diff
/// that drives what to upload. No CloudKit here, so it's fully unit-testable.
enum SyncRecords {
    /// The single non-entity record carrying app-level preferences.
    struct Prefs: Codable { var selectedTeamID: UUID }
    static let prefsID = "prefs"

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e
    }()
    private static let decoder = JSONDecoder()

    /// Every record that represents the given snapshot.
    static func records(from snapshot: AppSnapshot) -> [SyncRecord] {
        var records: [SyncRecord] = []
        records += encode(snapshot.teams, as: .team)
        records += encode(snapshot.players, as: .player)
        records += encode(snapshot.drills, as: .drill)
        records += encode(snapshot.sessions, as: .session)
        records += encode(snapshot.diagrams, as: .diagram)
        records += encode(snapshot.games, as: .game)
        records += encode(snapshot.events, as: .event)
        records += encode(snapshot.memberships, as: .rosterMembership)
        records += encode(snapshot.people, as: .person)
        records += encode(snapshot.userAccounts, as: .userAccount)
        records += encode(snapshot.organizations, as: .organization)
        records += encode(snapshot.orgMemberships, as: .orgMembership)
        records += encode(snapshot.shareGrants, as: .shareGrant)
        records += encode(snapshot.formTemplates, as: .formTemplate)
        records += encode(snapshot.formInstances, as: .formInstance)
        if let data = try? encoder.encode(Prefs(selectedTeamID: snapshot.selectedTeamID)) {
            records.append(SyncRecord(type: .prefs, id: prefsID, payload: data))
        }
        return records
    }

    /// The one record for a specific id (used to materialize a CKRecord on
    /// demand).
    ///
    /// Encodes only the entity that was asked for. `CKSyncEngine` calls this once
    /// per record in a batch, so routing it through `records(from:)` — which
    /// encodes every entity in the snapshot — cost one full-snapshot encode per
    /// record in the batch, making a push quadratic in the size of the coach's
    /// data. The bootstrap push, a single batch holding the whole season, is
    /// exactly the worst case.
    static func record(from snapshot: AppSnapshot, type: SyncRecordType, id: String) -> SyncRecord? {
        // Prefs is the one non-entity record: a singleton with a fixed id and no
        // backing collection to look up.
        if type == .prefs {
            guard id == prefsID,
                  let payload = try? encoder.encode(Prefs(selectedTeamID: snapshot.selectedTeamID))
            else { return nil }
            return SyncRecord(type: .prefs, id: prefsID, payload: payload)
        }

        guard let uuid = UUID(uuidString: id) else { return nil }
        switch type {
        case .team: return encode(snapshot.teams, id: uuid, as: .team)
        case .player: return encode(snapshot.players, id: uuid, as: .player)
        case .drill: return encode(snapshot.drills, id: uuid, as: .drill)
        case .session: return encode(snapshot.sessions, id: uuid, as: .session)
        case .diagram: return encode(snapshot.diagrams, id: uuid, as: .diagram)
        case .game: return encode(snapshot.games, id: uuid, as: .game)
        case .event: return encode(snapshot.events, id: uuid, as: .event)
        case .rosterMembership: return encode(snapshot.memberships, id: uuid, as: .rosterMembership)
        case .person: return encode(snapshot.people, id: uuid, as: .person)
        case .userAccount: return encode(snapshot.userAccounts, id: uuid, as: .userAccount)
        case .organization: return encode(snapshot.organizations, id: uuid, as: .organization)
        case .orgMembership: return encode(snapshot.orgMemberships, id: uuid, as: .orgMembership)
        case .shareGrant: return encode(snapshot.shareGrants, id: uuid, as: .shareGrant)
        case .formTemplate: return encode(snapshot.formTemplates, id: uuid, as: .formTemplate)
        case .formInstance: return encode(snapshot.formInstances, id: uuid, as: .formInstance)
        case .prefs: return nil // handled above
        }
    }

    /// Upserts a fetched record into a snapshot.
    static func apply(_ record: SyncRecord, to snapshot: inout AppSnapshot) {
        switch record.type {
        case .team: upsert(record.payload, into: &snapshot.teams)
        case .player: upsert(record.payload, into: &snapshot.players)
        case .drill: upsert(record.payload, into: &snapshot.drills)
        case .session: upsert(record.payload, into: &snapshot.sessions)
        case .diagram: upsert(record.payload, into: &snapshot.diagrams)
        case .game: upsert(record.payload, into: &snapshot.games)
        case .event: upsert(record.payload, into: &snapshot.events)
        case .rosterMembership: upsert(record.payload, into: &snapshot.memberships)
        case .person: upsert(record.payload, into: &snapshot.people)
        case .userAccount: upsert(record.payload, into: &snapshot.userAccounts)
        case .organization: upsert(record.payload, into: &snapshot.organizations)
        case .orgMembership: upsert(record.payload, into: &snapshot.orgMemberships)
        case .shareGrant: upsert(record.payload, into: &snapshot.shareGrants)
        case .formTemplate: upsert(record.payload, into: &snapshot.formTemplates)
        case .formInstance: upsert(record.payload, into: &snapshot.formInstances)
        case .prefs:
            if let prefs = try? decoder.decode(Prefs.self, from: record.payload) {
                snapshot.selectedTeamID = prefs.selectedTeamID
            }
        }
    }

    /// Removes a deleted record from a snapshot.
    static func delete(type: SyncRecordType, id: String, from snapshot: inout AppSnapshot) {
        guard let uuid = UUID(uuidString: id) else { return }
        switch type {
        case .team: snapshot.teams.removeAll { $0.id == uuid }
        case .player: snapshot.players.removeAll { $0.id == uuid }
        case .drill: snapshot.drills.removeAll { $0.id == uuid }
        case .session: snapshot.sessions.removeAll { $0.id == uuid }
        case .diagram: snapshot.diagrams.removeAll { $0.id == uuid }
        case .game: snapshot.games.removeAll { $0.id == uuid }
        case .event: snapshot.events.removeAll { $0.id == uuid }
        case .rosterMembership: snapshot.memberships.removeAll { $0.id == uuid }
        case .person: snapshot.people.removeAll { $0.id == uuid }
        case .userAccount: snapshot.userAccounts.removeAll { $0.id == uuid }
        case .organization: snapshot.organizations.removeAll { $0.id == uuid }
        case .orgMembership: snapshot.orgMemberships.removeAll { $0.id == uuid }
        case .shareGrant: snapshot.shareGrants.removeAll { $0.id == uuid }
        case .formTemplate: snapshot.formTemplates.removeAll { $0.id == uuid }
        case .formInstance: snapshot.formInstances.removeAll { $0.id == uuid }
        case .prefs: break
        }
    }

    /// A stable fingerprint of a payload, so the sync baseline can be remembered
    /// across launches without storing a second copy of the whole dataset.
    ///
    /// SHA-256 rather than `hashValue`: Swift seeds its hashing per process, so
    /// `hashValue` differs between launches and a watermark built from it would
    /// mark every record as changed on every launch.
    static func digest(_ payload: Data) -> String {
        SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
    }

    /// The fingerprint of every record in a set — the durable form of "what the
    /// remote has".
    static func digests(from records: [SyncRecord]) -> [SyncRecordKey: String] {
        Dictionary(records.map { (SyncRecordKey($0.type, $0.id), digest($0.payload)) },
                   uniquingKeysWith: { a, _ in a })
    }

    /// What changed since the baseline, as records to upload and keys to delete.
    ///
    /// Takes fingerprints rather than records so the caller can hold a baseline
    /// that survives relaunch: keeping whole payloads in memory meant the
    /// baseline was rebuilt from local data at every launch, which silently
    /// declared everything already synced and dropped any edit made while the
    /// remote was unreachable.
    static func diff(fromDigests old: [SyncRecordKey: String], to new: [SyncRecord])
        -> (upserts: [SyncRecord], deletes: [SyncRecordKey]) {
        let newKeys = Set(new.map { SyncRecordKey($0.type, $0.id) })
        let upserts = new.filter { old[SyncRecordKey($0.type, $0.id)] != digest($0.payload) }
        let deletes = old.keys.filter { !newKeys.contains($0) }
        return (upserts, deletes)
    }

    /// What changed between two record sets. Thin wrapper over the digest form.
    static func diff(from old: [SyncRecord], to new: [SyncRecord])
        -> (upserts: [SyncRecord], deletes: [SyncRecordKey]) {
        diff(fromDigests: digests(from: old), to: new)
    }

    // MARK: Helpers

    private static func encode<T: Identifiable & Codable>(_ items: [T], as type: SyncRecordType) -> [SyncRecord] where T.ID == UUID {
        items.compactMap { item in
            (try? encoder.encode(item)).map { SyncRecord(type: type, id: item.id.uuidString, payload: $0) }
        }
    }

    /// One entity's record. Shares `encoder` with the bulk `encode` above so the
    /// payload is byte-identical either way — `diff` compares payloads, so a
    /// difference in encoding would read as a spurious edit on every sync.
    private static func encode<T: Identifiable & Codable>(_ items: [T], id: UUID, as type: SyncRecordType) -> SyncRecord? where T.ID == UUID {
        guard let item = items.first(where: { $0.id == id }),
              let payload = try? encoder.encode(item) else { return nil }
        return SyncRecord(type: type, id: item.id.uuidString, payload: payload)
    }

    private static func upsert<T: Identifiable & Codable>(_ payload: Data, into array: inout [T]) where T.ID == UUID {
        guard let item = try? decoder.decode(T.self, from: payload) else { return }
        if let index = array.firstIndex(where: { $0.id == item.id }) {
            array[index] = item
        } else {
            array.append(item)
        }
    }
}

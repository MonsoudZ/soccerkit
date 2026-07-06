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
        if let data = try? encoder.encode(Prefs(selectedTeamID: snapshot.selectedTeamID)) {
            records.append(SyncRecord(type: .prefs, id: prefsID, payload: data))
        }
        return records
    }

    /// The one record for a specific id (used to materialize a CKRecord on demand).
    static func record(from snapshot: AppSnapshot, type: SyncRecordType, id: String) -> SyncRecord? {
        records(from: snapshot).first { $0.type == type && $0.id == id }
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
        case .prefs: break
        }
    }

    /// What changed between two snapshots, as records to upload and keys to delete.
    static func diff(from old: [SyncRecord], to new: [SyncRecord])
        -> (upserts: [SyncRecord], deletes: [SyncRecordKey]) {
        let oldMap = Dictionary(old.map { (SyncRecordKey($0.type, $0.id), $0.payload) }, uniquingKeysWith: { a, _ in a })
        let newKeys = Set(new.map { SyncRecordKey($0.type, $0.id) })

        let upserts = new.filter { oldMap[SyncRecordKey($0.type, $0.id)] != $0.payload }
        let deletes = old.compactMap { record -> SyncRecordKey? in
            let key = SyncRecordKey(record.type, record.id)
            return newKeys.contains(key) ? nil : key
        }
        return (upserts, deletes)
    }

    // MARK: Helpers

    private static func encode<T: Identifiable & Codable>(_ items: [T], as type: SyncRecordType) -> [SyncRecord] where T.ID == UUID {
        items.compactMap { item in
            (try? encoder.encode(item)).map { SyncRecord(type: type, id: item.id.uuidString, payload: $0) }
        }
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

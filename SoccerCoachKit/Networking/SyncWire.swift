import Foundation

/// One record on the wire: `{ "type": "Player", "id": "<uuid>", "payload": { … } }`.
/// `type` is a `SyncRecordType` raw value; `payload` is the entity's JSON.
struct SyncRecordDTO: Codable, Hashable {
    let type: String
    let id: String
    let payload: JSONValue
}

/// A tombstone: `{ "type": "Player", "id": "<uuid>" }`.
struct SyncKeyDTO: Codable, Hashable {
    let type: String
    let id: String
}

/// `POST /v1/sync` body — the local changes to apply, plus the client's cursor.
struct SyncPushRequest: Codable {
    var upserts: [SyncRecordDTO]
    var deletes: [SyncKeyDTO]
    var cursor: String?
}

/// `POST /v1/sync` response — server cursor, plus any records the server won a
/// conflict on (its version, which the client should adopt).
struct SyncPushResponse: Codable {
    var cursor: String?
    var conflicts: [SyncRecordDTO]

    init(cursor: String? = nil, conflicts: [SyncRecordDTO] = []) {
        self.cursor = cursor
        self.conflicts = conflicts
    }

    enum CodingKeys: String, CodingKey { case cursor, conflicts }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try c.decodeIfPresent(String.self, forKey: .cursor)
        conflicts = try c.decodeIfPresent([SyncRecordDTO].self, forKey: .conflicts) ?? []
    }
}

/// `GET /v1/sync?since=<cursor>` response — the delta since the cursor.
struct SyncPullResponse: Codable {
    var records: [SyncRecordDTO]
    var deletes: [SyncKeyDTO]
    var cursor: String?

    init(records: [SyncRecordDTO] = [], deletes: [SyncKeyDTO] = [], cursor: String? = nil) {
        self.records = records
        self.deletes = deletes
        self.cursor = cursor
    }

    enum CodingKeys: String, CodingKey { case records, deletes, cursor }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        records = try c.decodeIfPresent([SyncRecordDTO].self, forKey: .records) ?? []
        deletes = try c.decodeIfPresent([SyncKeyDTO].self, forKey: .deletes) ?? []
        cursor = try c.decodeIfPresent(String.self, forKey: .cursor)
    }
}

/// Converts between the app's internal `SyncRecord`/`SyncRecordKey` (payload is
/// raw `Data`) and the wire DTOs (payload is embedded JSON). Pure and testable —
/// the round-trip test doubles as the contract fixture for the backend.
enum SyncWireCodec {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys]; return e
    }()
    private static let decoder = JSONDecoder()

    static func dto(from record: SyncRecord) throws -> SyncRecordDTO {
        let payload = try decoder.decode(JSONValue.self, from: record.payload)
        return SyncRecordDTO(type: record.type.rawValue, id: record.id, payload: payload)
    }

    /// Returns `nil` for a record type this client version doesn't understand,
    /// so a newer server can't crash an older client.
    static func record(from dto: SyncRecordDTO) throws -> SyncRecord? {
        guard let type = SyncRecordType(rawValue: dto.type) else { return nil }
        let data = try encoder.encode(dto.payload)
        return SyncRecord(type: type, id: dto.id, payload: data)
    }

    static func keyDTO(from key: SyncRecordKey) -> SyncKeyDTO {
        SyncKeyDTO(type: key.type.rawValue, id: key.id)
    }

    static func key(from dto: SyncKeyDTO) -> SyncRecordKey? {
        SyncRecordType(rawValue: dto.type).map { SyncRecordKey($0, dto.id) }
    }
}

import Foundation

/// A fully-general JSON value. Used to carry an entity's already-encoded payload
/// as a real embedded JSON object on the wire (rather than a base64 blob or a
/// double-encoded string), so the Go backend can unmarshal `payload` straight
/// into the matching struct.
///
/// Note on dates: entity payloads are produced by `SyncRecords`' `JSONEncoder`,
/// whose default date strategy encodes `Date` as a `Double` (seconds since
/// 2001-01-01). The backend should treat each record `payload` as an opaque JSON
/// document for storage/echo; only fields it needs to query (ids, org_id,
/// updated_at) should be lifted out, and date fields parsed with that in mind.
enum JSONValue: Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

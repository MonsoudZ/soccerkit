import XCTest
@testable import SoccerCoachKit

/// The wire contract between the app and the Go backend. These round-trips are
/// the fixture the backend implements against: a record is
/// `{type, id, payload:{…}}`, payload is the entity's own JSON, and unknown
/// types are skipped rather than fatal.
final class SyncWireTests: XCTestCase {

    func testJSONValueRoundTrips() throws {
        let value: JSONValue = .object([
            "n": .number(3), "s": .string("x"), "b": .bool(true),
            "arr": .array([.string("a"), .null]), "nil": .null
        ])
        let data = try JSONEncoder().encode(value)
        let back = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(back, value)
    }

    func testSyncRecordBecomesEnvelopeWithEmbeddedPayload() throws {
        let person = Person(id: UUID(), name: "Ana Costa", guardian: "Guardian", medicalNotes: "None")
        let payload = try JSONEncoder().encode(person)
        let record = SyncRecord(type: .person, id: person.id.uuidString, payload: payload)

        let dto = try SyncWireCodec.dto(from: record)
        XCTAssertEqual(dto.type, "Person")
        XCTAssertEqual(dto.id, person.id.uuidString)
        // payload is a real embedded object, not a string/blob.
        guard case .object(let fields) = dto.payload else { return XCTFail("payload not an object") }
        XCTAssertEqual(fields["name"], .string("Ana Costa"))

        // And it decodes straight back to the same entity.
        let back = try SyncWireCodec.record(from: dto)
        XCTAssertNotNil(back)
        let decoded = try JSONDecoder().decode(Person.self, from: back!.payload)
        XCTAssertEqual(decoded, person)
    }

    func testUnknownRecordTypeIsSkipped() throws {
        let dto = SyncRecordDTO(type: "Martian", id: UUID().uuidString, payload: .object([:]))
        XCTAssertNil(try SyncWireCodec.record(from: dto), "a newer server's type can't crash an older client")
    }

    func testTombstoneKeyRoundTrips() {
        let key = SyncRecordKey(.team, UUID().uuidString)
        let dto = SyncWireCodec.keyDTO(from: key)
        XCTAssertEqual(dto.type, "Team")
        XCTAssertEqual(SyncWireCodec.key(from: dto), key)
    }

    func testEveryRecordTypeSurvivesTheRoundTrip() throws {
        // A snapshot exercising the seams; every record it produces must survive
        // record → dto → record with its type intact.
        let snapshot = TestData.snapshot(playerCount: 3)
        for record in SyncRecords.records(from: snapshot) {
            let dto = try SyncWireCodec.dto(from: record)
            let back = try SyncWireCodec.record(from: dto)
            XCTAssertEqual(back?.type, record.type)
            XCTAssertEqual(back?.id, record.id)
        }
    }

    func testPushRequestShape() throws {
        let request = SyncPushRequest(
            upserts: [SyncRecordDTO(type: "Team", id: "t1", payload: .object(["name": .string("FC")]))],
            deletes: [SyncKeyDTO(type: "Player", id: "p1")],
            cursor: "c1"
        )
        let data = try JSONEncoder().encode(request)
        let object = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertNotNil(object["upserts"])
        XCTAssertNotNil(object["deletes"])
        XCTAssertEqual(object["cursor"] as? String, "c1")

        let decoded = try JSONDecoder().decode(SyncPushRequest.self, from: data)
        XCTAssertEqual(decoded.upserts.first?.type, "Team")
        XCTAssertEqual(decoded.deletes.first?.id, "p1")
    }

    func testResponsesTolerateMissingFields() throws {
        let pull = try JSONDecoder().decode(SyncPullResponse.self,
                                            from: #"{"cursor":"x"}"#.data(using: .utf8)!)
        XCTAssertTrue(pull.records.isEmpty)
        XCTAssertTrue(pull.deletes.isEmpty)
        XCTAssertEqual(pull.cursor, "x")

        let push = try JSONDecoder().decode(SyncPushResponse.self, from: "{}".data(using: .utf8)!)
        XCTAssertTrue(push.conflicts.isEmpty)
        XCTAssertNil(push.cursor)
    }
}

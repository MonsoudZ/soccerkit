import XCTest
@testable import SoccerCoachKit

/// The polymorphic ShareGrant seam: sharing is one scoped table, defaulting to
/// private, with the org-scope "club library" query falling out for free.
final class ShareGrantTests: XCTestCase {

    func testDefaultsToPrivateAndEmpty() {
        let snapshot = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                   games: [], events: [], selectedTeamID: UUID())
        XCTAssertTrue(snapshot.shareGrants.isEmpty)
    }

    func testExpiryGatesActive() {
        let past = Date(timeIntervalSince1970: 1_000)
        let future = Date(timeIntervalSince1970: 4_000)
        let now = Date(timeIntervalSince1970: 2_000)
        let expired = ShareGrant(shareableType: .session, shareableID: UUID(), scope: .org, expiresAt: past)
        let live = ShareGrant(shareableType: .session, shareableID: UUID(), scope: .org, expiresAt: future)
        let evergreen = ShareGrant(shareableType: .session, shareableID: UUID(), scope: .org)
        XCTAssertFalse(expired.isActive(asOf: now))
        XCTAssertTrue(live.isActive(asOf: now))
        XCTAssertTrue(evergreen.isActive(asOf: now))
    }

    func testGrantSyncsAsRecord() {
        let grant = ShareGrant(shareableType: .drill, shareableID: UUID(), scope: .org)
        let source = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                 games: [], events: [], selectedTeamID: UUID(), shareGrants: [grant])
        let records = SyncRecords.records(from: source)
        XCTAssertTrue(records.contains { $0.type == .shareGrant && $0.id == grant.id.uuidString })

        var target = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                 games: [], events: [], selectedTeamID: source.selectedTeamID)
        for record in records { SyncRecords.apply(record, to: &target) }
        XCTAssertEqual(target.shareGrants, [grant])
    }
}

@MainActor
final class ShareGrantStoreTests: XCTestCase {

    func testSetAndClearScope() {
        let store = TestData.store()
        let sessionID = UUID()
        XCTAssertEqual(store.shareScope(ofType: .session, id: sessionID), .privateOnly)

        store.setShareScope(.org, forType: .session, id: sessionID)
        XCTAssertEqual(store.shareScope(ofType: .session, id: sessionID), .org)
        XCTAssertEqual(store.shareGrants.count, 1)

        // Re-scoping the same shareable updates rather than duplicates.
        store.setShareScope(.team, forType: .session, id: sessionID)
        XCTAssertEqual(store.shareGrants.count, 1)
        XCTAssertEqual(store.shareScope(ofType: .session, id: sessionID), .team)

        // Back to private drops the grant entirely.
        store.setShareScope(.privateOnly, forType: .session, id: sessionID)
        XCTAssertTrue(store.shareGrants.isEmpty)
        XCTAssertEqual(store.shareScope(ofType: .session, id: sessionID), .privateOnly)
    }

    func testOrgLibraryIsEverythingOrgScoped() {
        let store = TestData.store()
        let org = Organization.personalID
        let shared1 = UUID(), shared2 = UUID(), teamOnly = UUID()
        store.setShareScope(.org, forType: .drill, id: shared1)
        store.setShareScope(.org, forType: .drill, id: shared2)
        store.setShareScope(.team, forType: .drill, id: teamOnly)

        let library = Set(store.orgLibraryIDs(ofType: .drill, in: org))
        XCTAssertEqual(library, [shared1, shared2], "the club library is just org-scoped grants")
        XCTAssertFalse(library.contains(teamOnly))
    }
}

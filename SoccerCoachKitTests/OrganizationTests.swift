import XCTest
@testable import SoccerCoachKit

/// The Organization / OrgMembership / Role seam: every team belongs to an org,
/// roles are a join (never a column), and the solo coach owns their personal org
/// with admin+director+coach.
final class OrganizationTests: XCTestCase {

    // MARK: - Migration & defaults

    func testTeamDefaultsToPersonalOrg() {
        let team = TestData.team()
        XCTAssertEqual(team.organizationID, Organization.personalID)
    }

    func testLegacyTeamDecodesToPersonalOrg() throws {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Old FC","ageGroup":"U12","season":"2026","accentName":"Teal"}
        """.data(using: .utf8)!
        let team = try JSONDecoder().decode(Team.self, from: json)
        XCTAssertEqual(team.organizationID, Organization.personalID, "pre-org teams migrate to the personal org")
    }

    func testSnapshotAlwaysHasThePersonalOrg() {
        let snapshot = AppSnapshot(teams: [TestData.team()], players: [], drills: [], sessions: [],
                                   diagrams: [], games: [], events: [], selectedTeamID: UUID())
        XCTAssertTrue(snapshot.organizations.contains { $0.id == Organization.personalID })
        XCTAssertEqual(snapshot.organizations.first { $0.id == Organization.personalID }?.kind, .personal)
    }

    func testPersonalOrgNotDuplicatedWhenPresent() {
        let custom = Organization(id: UUID(), name: "Real Club", kind: .club)
        let snapshot = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                   games: [], events: [], selectedTeamID: UUID(),
                                   organizations: [.personal, custom])
        XCTAssertEqual(snapshot.organizations.filter { $0.id == Organization.personalID }.count, 1)
        XCTAssertTrue(snapshot.organizations.contains { $0.kind == .club })
    }

    // MARK: - Permission matrix

    func testPermissionMatrixMatchesTheDoc() {
        XCTAssertTrue(Permissions.can(.manageOrg, asAnyOf: [.admin]))
        XCTAssertFalse(Permissions.can(.manageOrg, asAnyOf: [.director, .coach]))

        XCTAssertTrue(Permissions.can(.seeEveryTeam, asAnyOf: [.director]))
        XCTAssertFalse(Permissions.can(.seeEveryTeam, asAnyOf: [.coach]))

        XCTAssertTrue(Permissions.can(.runSessions, asAnyOf: [.coach]))
        XCTAssertTrue(Permissions.can(.evaluateAthletes, asAnyOf: [.coach]))

        XCTAssertTrue(Permissions.can(.fillCheckIn, asAnyOf: [.parent]))
        XCTAssertTrue(Permissions.can(.fillCheckIn, asAnyOf: [.player]))
        XCTAssertFalse(Permissions.can(.fillCheckIn, asAnyOf: [.coach]))

        XCTAssertTrue(Permissions.can(.seeAthleteRecord, asAnyOf: [.parent]))
        XCTAssertFalse(Permissions.can(.evaluateAthletes, asAnyOf: [.parent]))
    }

    // MARK: - Sync

    func testOrgAndMembershipSyncAsRecords() {
        let org = Organization(id: UUID(), name: "Club", kind: .club)
        let membership = OrgMembership(personID: UUID(), organizationID: org.id, roles: [.director, .coach])
        let source = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                 games: [], events: [], selectedTeamID: UUID(),
                                 organizations: [org], orgMemberships: [membership])
        let records = SyncRecords.records(from: source)
        XCTAssertTrue(records.contains { $0.type == .organization && $0.id == org.id.uuidString })
        XCTAssertTrue(records.contains { $0.type == .orgMembership && $0.id == membership.id.uuidString })

        var target = AppSnapshot(teams: [], players: [], drills: [], sessions: [], diagrams: [],
                                 games: [], events: [], selectedTeamID: source.selectedTeamID)
        for record in records { SyncRecords.apply(record, to: &target) }
        XCTAssertTrue(target.orgMemberships.contains(membership), "roles set survives the round trip")
    }
}

@MainActor
final class OrganizationStoreTests: XCTestCase {

    func testEnsureOwnerCreatesLinkedPersonAccountAndRoles() {
        let store = TestData.store()
        store.ensureOwner(appleUserID: "apple-owner", displayName: "Coach Zed")

        let account = store.userAccount(appleUserID: "apple-owner")
        XCTAssertNotNil(account?.personID, "account is now linked to a Person")
        let ownerID = account!.personID!
        XCTAssertEqual(store.person(id: ownerID)?.name, "Coach Zed")
        XCTAssertEqual(store.roles(ofPerson: ownerID, in: Organization.personalID), [.admin, .director, .coach])

        // The solo coach lights up the coach-tier capabilities...
        XCTAssertTrue(store.can(.runSessions, person: ownerID, in: Organization.personalID))
        XCTAssertTrue(store.can(.manageOrg, person: ownerID, in: Organization.personalID))
        // ...and a stranger holds nothing.
        XCTAssertFalse(store.can(.runSessions, person: UUID(), in: Organization.personalID))
    }

    func testEnsureOwnerIsIdempotent() {
        let store = TestData.store()
        store.ensureOwner(appleUserID: "apple-owner", displayName: "Coach")
        store.ensureOwner(appleUserID: "apple-owner", displayName: "Coach")
        XCTAssertEqual(store.userAccounts.filter { $0.appleUserID == "apple-owner" }.count, 1)
        let ownerID = store.userAccount(appleUserID: "apple-owner")!.personID!
        XCTAssertEqual(store.orgMemberships.filter { $0.personID == ownerID }.count, 1)
    }

    func testTeamsResolveToTheirOrganization() {
        let store = TestData.store()
        let team = store.selectedTeam
        XCTAssertEqual(store.organization(for: team)?.id, Organization.personalID)
        XCTAssertEqual(store.personalOrg.kind, .personal)
    }
}

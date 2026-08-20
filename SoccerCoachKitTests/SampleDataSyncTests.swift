import XCTest
@testable import SoccerCoachKit

/// The sample seed looks exactly like real data, and a returning coach's second
/// device shows it while their season is still downloading. That combination used
/// to merge the demo team into their account and — worse — make a later "Reset"
/// or onboarding "Create My Team" push a delete for every record they owned.
@MainActor
final class SampleDataSyncTests: XCTestCase {
    private var mock: MockRemoteSync!
    private var realTeam: Team!

    override func setUp() {
        super.setUp()
        mock = MockRemoteSync()
        realTeam = TestData.team()
    }

    /// A store that launched onto the seed, with sync switched on — a coach's
    /// second device in the seconds before their data arrives.
    private func seededStore() -> AppStore {
        let store = AppStore(snapshot: SampleData.snapshot,
                             persistence: InMemoryPersistence(), remoteSync: mock)
        store.cloudSyncEnabled = true
        store.flushPendingRemoteSync()
        return store
    }

    /// The coach's own season landing from the server.
    private func deliverRealSeason() {
        let season = AppSnapshot(teams: [realTeam], players: [], drills: [], sessions: [],
                                 diagrams: [], games: [], events: [], selectedTeamID: realTeam.id)
        mock.applyRemoteChanges?(SyncRecords.records(from: season), [])
    }

    private var allPushedDeletes: [SyncRecordKey] { mock.pushedDeletes.flatMap { $0 } }
    private var allPushedUpserts: [SyncRecord] { mock.pushedUpserts.flatMap { $0 } }

    // MARK: - Recognising the seed

    func testAnUntouchedSeedIsAPlaceholderAndAnythingElseIsNot() {
        XCTAssertTrue(SampleData.isPlaceholder(SampleData.snapshot))

        var edited = SampleData.snapshot
        edited.teams.append(TestData.team())
        XCTAssertFalse(SampleData.isPlaceholder(edited), "Adding a team makes it the coach's own")

        var trimmed = SampleData.snapshot
        trimmed.players.removeFirst()
        XCTAssertFalse(SampleData.isPlaceholder(trimmed), "So does removing a player")

        XCTAssertFalse(SampleData.isPlaceholder(TestData.snapshot()), "Unrelated data is not the seed")
    }

    /// The seed's content is rebuilt on every read (its development-log dates are
    /// relative to now), so recognition has to key off identity, not bytes.
    func testSeedIsRecognisedAcrossSeparateReadsOfIt() {
        XCTAssertTrue(SampleData.isPlaceholder(SampleData.snapshot))
        XCTAssertTrue(SampleData.isPlaceholder(SampleData.snapshot))
    }

    // MARK: - The seed is not the coach's data

    func testSeedIsNeverPushed() {
        let store = seededStore()
        XCTAssertTrue(store.isShowingSeedData)
        XCTAssertTrue(allPushedUpserts.isEmpty, "A placeholder is not the coach's data to upload")
    }

    func testRealDataReplacesTheSeedRatherThanMergingIntoIt() {
        let store = seededStore()
        let seedIDs = Set(SampleData.snapshot.teams.map(\.id))
        XCTAssertTrue(store.teams.contains { seedIDs.contains($0.id) }, "Precondition: the demo team is showing")

        deliverRealSeason()

        XCTAssertTrue(store.teams.contains { $0.id == realTeam.id }, "The coach's season arrives")
        XCTAssertFalse(store.teams.contains { seedIDs.contains($0.id) },
                       "...and the demo team does not sit beside it")
        XCTAssertFalse(store.isShowingSeedData, "The placeholder is gone")
        XCTAssertEqual(store.selectedTeamID, realTeam.id)
    }

    func testKeepingTheSeedAndEditingItUploadsAllOfIt() {
        let store = seededStore()
        let seedTeamIDs = Set(SampleData.snapshot.teams.map(\.id.uuidString))

        // The coach explores the sample data and decides to keep it, adding their
        // own team alongside. The seed is theirs now.
        store.addTeam(name: "My Team", ageGroup: .u10, season: "2026")
        store.flushPendingRemoteSync()

        XCTAssertFalse(store.isShowingSeedData)
        let uploadedTeamIDs = Set(allPushedUpserts.filter { $0.type == .team }.map(\.id))
        XCTAssertTrue(seedTeamIDs.isSubset(of: uploadedTeamIDs),
                      "Adopting the seed uploads the whole thing, not just the edit that adopted it")
    }

    // MARK: - Nothing wipes the account

    func testResettingToSampleDataDoesNotDeleteTheSyncedSeason() {
        let store = seededStore()
        deliverRealSeason()
        mock.pushedDeletes.removeAll()

        store.resetToSampleData()
        store.flushPendingRemoteSync()

        XCTAssertTrue(allPushedDeletes.isEmpty,
                      "Resetting this device must not tombstone the coach's account")
        XCTAssertTrue(store.isShowingSeedData, "The device is back to a placeholder")
    }

    func testOnboardingCreateMyTeamDoesNotDeleteTheSyncedSeason() {
        let store = seededStore()
        deliverRealSeason()
        mock.pushedDeletes.removeAll()

        // hasOnboarded is per-device, so a coach adding a second device runs
        // onboarding again — with their real season already downloaded behind it.
        store.startFresh(name: "New FC", ageGroup: .u10, season: "2026", accent: .teal)
        store.flushPendingRemoteSync()

        XCTAssertTrue(allPushedDeletes.isEmpty,
                      "Creating a team must not tombstone the coach's account")
        XCTAssertTrue(store.teams.contains { $0.id == realTeam.id }, "Their season is untouched")
        XCTAssertTrue(store.teams.contains { $0.name == "New FC" }, "...and the new team was added")
        XCTAssertEqual(store.selectedTeam.name, "New FC", "...and selected")
    }

    func testCreateMyTeamStillReplacesTheSeedWhenThereIsNoRealData() {
        let store = seededStore()

        store.startFresh(name: "New FC", ageGroup: .u10, season: "2026", accent: .teal)
        store.flushPendingRemoteSync()

        XCTAssertEqual(store.teams.count, 1, "A first-time coach gets a clean start, not the demo teams")
        XCTAssertEqual(store.teams.first?.name, "New FC")
        XCTAssertTrue(allPushedDeletes.isEmpty, "Nothing was on the server to delete")
    }
}

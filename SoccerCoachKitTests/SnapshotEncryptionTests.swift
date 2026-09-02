import XCTest
@testable import SoccerCoachKit

/// The snapshot is a squad of children: allergies and medical notes, guardian
/// and emergency contact names, phone numbers, email addresses. It used to be
/// written to `UserDefaults` as plain JSON, which put all of it in readable text
/// inside any unencrypted device backup and in front of anything with access to
/// the app container.
@MainActor
final class SnapshotEncryptionTests: XCTestCase {
    private var defaults: UserDefaults!
    private var keyStore: InMemoryTokenStorage!
    private let storageKey = "SoccerCoachKit.AppSnapshot.v1"

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "snapshot-encryption-\(UUID().uuidString)")!
        keyStore = InMemoryTokenStorage()
    }

    /// A service sharing this test's key store, so a second one stands in for the
    /// same app on a later launch.
    private func makeService() -> UserDefaultsPersistenceService {
        UserDefaultsPersistenceService(
            defaults: defaults,
            cipher: KeychainSnapshotCipher(storage: keyStore)
        )
    }

    /// A roster carrying exactly the fields worth protecting.
    private func snapshotWithMedicalData() -> AppSnapshot {
        let team = TestData.team()
        var player = TestData.player(teamID: team.id, number: 7)
        player.name = "Rosa Delgado"
        player.guardianPhone = "555-0147"
        player.guardianEmail = "guardian@example.test"
        player.emergencyContactPhone = "555-0199"
        player.allergies = "Severe peanut allergy"
        player.medicalNotes = "Carries an EpiPen in the kit bag"
        return AppSnapshot(teams: [team], players: [player], drills: [], sessions: [],
                           diagrams: [], games: [], events: [], selectedTeamID: team.id)
    }

    /// Everything a reader of the raw bytes must not find.
    private let secrets = [
        "Rosa Delgado", "555-0147", "guardian@example.test", "555-0199",
        "Severe peanut allergy", "Carries an EpiPen in the kit bag",
        "medicalNotes", "allergies", "guardianPhone",
    ]

    private func assertNoSecrets(in data: Data, _ message: String,
                                file: StaticString = #filePath, line: UInt = #line) {
        // Search the bytes, not a decoded string: the point is that nothing in
        // there reads back as the coach's data however it's interpreted.
        let text = String(decoding: data, as: UTF8.self)
        for secret in secrets {
            XCTAssertFalse(text.contains(secret), "\(message) — found \"\(secret)\"",
                           file: file, line: line)
        }
    }

    // MARK: - At rest

    func testAStoredSnapshotIsNotReadable() {
        let service = makeService()
        service.save(snapshotWithMedicalData())
        service.flushPendingSync()

        let stored = defaults.data(forKey: storageKey)
        XCTAssertNotNil(stored, "something must have been written")
        assertNoSecrets(in: stored!, "the roster is readable in UserDefaults")
    }

    func testTheAppCanStillReadItsOwnSnapshot() {
        let service = makeService()
        let original = snapshotWithMedicalData()
        service.save(original)
        service.flushPendingSync()

        // A later launch: same key store, new service.
        guard case .success(let loaded) = makeService().load() else {
            return XCTFail("the app must be able to read back what it wrote")
        }
        XCTAssertEqual(loaded.players.first?.medicalNotes, "Carries an EpiPen in the kit bag")
        XCTAssertEqual(loaded.players.first?.guardianPhone, "555-0147")
        XCTAssertEqual(loaded.teams.first?.id, original.teams.first?.id)
    }

    // MARK: - Migration

    /// A coach upgrading has a plaintext snapshot already on disk. It must still
    /// load — and must not be left sitting there in the clear afterwards.
    func testAPlaintextSnapshotIsReadAndThenSealed() throws {
        let original = snapshotWithMedicalData()
        let plaintext = try JSONEncoder().encode(original)
        assertNoSecrets(in: try JSONEncoder().encode(1),
                        "sanity: the matcher shouldn't fire on unrelated bytes")
        XCTAssertTrue(String(decoding: plaintext, as: UTF8.self).contains("Severe peanut allergy"),
                      "the fixture really is readable before migration")
        defaults.set(plaintext, forKey: storageKey)

        let service = makeService()
        guard case .success(let loaded) = service.load() else {
            return XCTFail("an upgrading coach must not lose their season")
        }
        XCTAssertEqual(loaded.players.first?.allergies, "Severe peanut allergy")

        service.flushPendingSync()
        assertNoSecrets(in: defaults.data(forKey: storageKey)!,
                        "the old plaintext was left on disk after migrating")
    }

    // MARK: - When the key is gone

    /// Restored to a device whose Keychain didn't come with it: the snapshot is
    /// unreadable, not worthless. It must be preserved rather than overwritten,
    /// the same as any other undecodable blob.
    func testAnUnreadableSnapshotIsPreservedNotDestroyed() {
        let service = makeService()
        service.save(snapshotWithMedicalData())
        service.flushPendingSync()
        let sealed = defaults.data(forKey: storageKey)

        // A new device: same bytes, no key.
        let restored = UserDefaultsPersistenceService(
            defaults: defaults,
            cipher: KeychainSnapshotCipher(storage: InMemoryTokenStorage())
        )
        guard case .corrupt(let data, _) = restored.load() else {
            return XCTFail("ciphertext with no key must not read as empty or succeed")
        }
        XCTAssertEqual(data, sealed, "the unreadable bytes are handed back intact")
        XCTAssertEqual(defaults.data(forKey: storageKey), sealed,
                       "and left in place, not cleared")
    }

    /// A key the Keychain refuses to store must fail the write rather than fall
    /// back to plaintext — silently writing the roster in the clear is the exact
    /// outcome this guards against.
    func testAWriteThatCannotBeSealedIsNotWrittenInTheClear() {
        let service = UserDefaultsPersistenceService(
            defaults: defaults,
            cipher: KeychainSnapshotCipher(storage: FailingTokenStorage())
        )
        service.save(snapshotWithMedicalData())
        service.flushPendingSync()

        if let written = defaults.data(forKey: storageKey) {
            assertNoSecrets(in: written, "a snapshot that couldn't be sealed was written anyway")
        }
    }

    /// The corrupt-data escape hatch has to survive encryption. A snapshot that
    /// decrypts but won't decode is the recoverable case, so what the coach
    /// exports must be readable — while the copy left on disk stays sealed.
    func testARecoverableCorruptBackupExportsReadable() throws {
        // Sealed, but the plaintext inside isn't a snapshot.
        let cipher = KeychainSnapshotCipher(storage: keyStore)
        let damaged = Data(#"{"teams":[],"players":"Rosa Delgado"}"#.utf8)
        defaults.set(try cipher.seal(damaged), forKey: storageKey)

        let service = makeService()
        guard case .corrupt(let bytes, _) = service.load() else {
            return XCTFail("a snapshot that decrypts but won't decode is corrupt")
        }
        service.backupCorruptData(bytes)

        assertNoSecrets(in: defaults.data(forKey: storageKey + ".corrupt-backup")!,
                        "the preserved copy must stay sealed on disk")
        XCTAssertEqual(service.corruptBackup(), damaged,
                       "but what the coach exports must be readable")
    }

    // MARK: - The cipher itself

    func testSealingIsNotEncoding() throws {
        let cipher = KeychainSnapshotCipher(storage: keyStore)
        let plaintext = Data("Carries an EpiPen in the kit bag".utf8)
        let sealed = try cipher.seal(plaintext)
        XCTAssertNotEqual(sealed, plaintext)
        assertNoSecrets(in: sealed, "seal returned something readable")
        XCTAssertEqual(try cipher.open(sealed), plaintext)
    }

    /// Two seals of the same bytes differ, so the stored blob doesn't leak that
    /// nothing changed between two saves.
    func testSealingIsNonDeterministic() throws {
        let cipher = KeychainSnapshotCipher(storage: keyStore)
        let plaintext = Data("Severe peanut allergy".utf8)
        XCTAssertNotEqual(try cipher.seal(plaintext), try cipher.seal(plaintext))
    }

    func testAnotherKeyCannotOpenIt() throws {
        let sealed = try KeychainSnapshotCipher(storage: keyStore).seal(Data("secret".utf8))
        let stranger = KeychainSnapshotCipher(storage: InMemoryTokenStorage())
        XCTAssertThrowsError(try stranger.open(sealed))
    }

    /// Signing out clears the session tokens. It must not take the key to the
    /// coach's own data with it, which is why the key lives in its own service.
    func testTheDataKeyIsNotASessionToken() {
        let shared = InMemoryTokenStorage()
        let tokens = TokenStore(storage: shared)
        tokens.token = "access"
        tokens.refreshToken = "refresh"
        _ = try? KeychainSnapshotCipher(storage: shared).seal(Data("x".utf8))

        tokens.clear()

        XCTAssertNil(tokens.token)
        XCTAssertNotNil(shared.string(forKey: "snapshotEncryptionKey"),
                        "signing out must not destroy the key to the roster")
    }
}

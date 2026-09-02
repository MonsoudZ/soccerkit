import CryptoKit
import Foundation

/// Encrypts the persisted snapshot at rest.
///
/// The snapshot holds the roster, and the roster holds children: `Person` and
/// `Player` carry allergies and medical notes alongside guardian and emergency
/// contact names, phone numbers and email addresses. Written as plain JSON —
/// which is how the app started — that lands in two places worth worrying
/// about. An unencrypted iTunes/Finder backup puts the whole squad's medical
/// details on a computer in readable text, and anything with filesystem access
/// to the container reads them directly. iOS file protection alone doesn't help
/// much here: the app needs its data after first unlock so background sync can
/// run, which is the same class `UserDefaults` already uses.
///
/// Sealing the blob closes both. The key lives in the Keychain, so the bytes on
/// disk are ciphertext no matter who reads them.
protocol SnapshotCipher {
    func seal(_ data: Data) throws -> Data
    func open(_ data: Data) throws -> Data
}

enum SnapshotCipherError: Error {
    /// No key could be read or created — see `KeychainSnapshotCipher`.
    case keyUnavailable
}

/// AES-GCM with a 256-bit key kept in the Keychain.
///
/// The key is deliberately *not* `ThisDeviceOnly`, and the interaction with
/// backups is the reason:
///
/// - An **unencrypted** backup carries the sealed snapshot but not a usable
///   key, so the medical details aren't readable on the computer holding it.
///   That is the vector this exists to close.
/// - An **encrypted** backup carries both, so a coach who restores to a new
///   phone keeps their season — and the backup was encrypted anyway.
///
/// It sits in its own Keychain service rather than beside the session tokens,
/// so signing out (which clears those) can't take the key to the coach's data
/// with it.
final class KeychainSnapshotCipher: SnapshotCipher {
    private let storage: TokenStorage
    private let account: String

    init(storage: TokenStorage = KeychainTokenStorage(
            service: (Bundle.main.bundleIdentifier ?? "SoccerCoachKit") + ".datakey"),
         account: String = "snapshotEncryptionKey") {
        self.storage = storage
        self.account = account
    }

    func seal(_ data: Data) throws -> Data {
        let sealed = try AES.GCM.seal(data, using: try keyForWriting())
        guard let combined = sealed.combined else { throw SnapshotCipherError.keyUnavailable }
        return combined
    }

    func open(_ data: Data) throws -> Data {
        // Reading never mints a key: if there isn't one, this blob can't be ours
        // to read, and creating one here would only mask that.
        guard let key = existingKey() else { throw SnapshotCipherError.keyUnavailable }
        return try AES.GCM.open(try AES.GCM.SealedBox(combined: data), using: key)
    }

    private func existingKey() -> SymmetricKey? {
        guard let stored = storage.string(forKey: account),
              let raw = Data(base64Encoded: stored) else { return nil }
        return SymmetricKey(data: raw)
    }

    /// The key to seal with, minting one on first use.
    ///
    /// Throws rather than falling back when the Keychain won't take it. A write
    /// that can't be sealed must not be written in the clear — that is the whole
    /// point — and the caller keeps the snapshot in memory, so the next save
    /// once the device is unlocked gets another go.
    private func keyForWriting() throws -> SymmetricKey {
        if let existing = existingKey() { return existing }
        let fresh = SymmetricKey(size: .bits256)
        let encoded = fresh.withUnsafeBytes { Data($0) }.base64EncodedString()
        guard storage.set(encoded, forKey: account) else { throw SnapshotCipherError.keyUnavailable }
        return fresh
    }
}

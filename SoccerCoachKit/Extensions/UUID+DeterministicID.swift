import CryptoKit
import Foundation

extension UUID {
    /// An RFC 4122 v5 (SHA-1, name-based) UUID. Deterministic: the same
    /// `namespace` + `name` always yields the same UUID, on every device.
    ///
    /// Byte-for-byte compatible with Go's `uuid.NewSHA1(namespace, []byte(name))`
    /// — both hash the namespace's 16 bytes followed by the name's UTF-8 bytes,
    /// then stamp version 5 and the RFC 4122 variant. The backend relies on this
    /// match to reconcile the coach's account Person with the synced Person.
    static func v5(namespace: UUID, name: String) -> UUID {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: namespace.uuid) { bytes.append(contentsOf: $0) }
        bytes.append(contentsOf: Array(name.utf8))

        var d = Array(Insecure.SHA1.hash(data: Data(bytes))) // 20 bytes
        d[6] = (d[6] & 0x0F) | 0x50 // version 5
        d[8] = (d[8] & 0x3F) | 0x80 // RFC 4122 variant

        return UUID(uuid: (d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7],
                           d[8], d[9], d[10], d[11], d[12], d[13], d[14], d[15]))
    }
}

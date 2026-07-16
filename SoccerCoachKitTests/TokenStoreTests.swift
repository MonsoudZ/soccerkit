import XCTest
@testable import SoccerCoachKit

final class TokenStoreTests: XCTestCase {
    func testStoresReadsAndClearsTokens() {
        let store = TokenStore(storage: InMemoryTokenStorage())
        XCTAssertNil(store.token)
        XCTAssertNil(store.refreshToken)

        store.token = "access"
        store.refreshToken = "refresh"
        XCTAssertEqual(store.token, "access")
        XCTAssertEqual(store.refreshToken, "refresh")

        store.clear()
        XCTAssertNil(store.token)
        XCTAssertNil(store.refreshToken)
    }

    /// The access and refresh tokens are independent slots — clearing one must
    /// not drop the other (the refresh flow relies on this).
    func testAccessAndRefreshAreIndependent() {
        let store = TokenStore(storage: InMemoryTokenStorage())
        store.token = "a"
        store.refreshToken = "r"

        store.token = nil
        XCTAssertNil(store.token)
        XCTAssertEqual(store.refreshToken, "r")
    }

    /// Exercises the real Keychain seam behind `TokenStore` — insert, update, and
    /// delete. Uses a unique service per run so parallel tests don't collide.
    /// Skipped where the test host can't reach the keychain.
    func testKeychainRoundTrip() throws {
        let keychain = KeychainTokenStorage(service: "soccerkit.tests.\(UUID().uuidString)")

        keychain.set("v1", forKey: "k")
        guard keychain.string(forKey: "k") != nil else {
            throw XCTSkip("Keychain not available in this test host")
        }
        XCTAssertEqual(keychain.string(forKey: "k"), "v1")

        keychain.set("v2", forKey: "k") // update path
        XCTAssertEqual(keychain.string(forKey: "k"), "v2")

        keychain.set(nil, forKey: "k") // delete path
        XCTAssertNil(keychain.string(forKey: "k"))
    }
}

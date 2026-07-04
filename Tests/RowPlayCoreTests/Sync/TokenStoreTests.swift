import XCTest
@testable import RowPlayCore

final class TokenStoreTests: XCTestCase {
    // MARK: - FakeTokenStore

    func testFakeTokenStoreInitializesEmpty() throws {
        let store = FakeTokenStore()
        XCTAssertNil(try store.loadToken())
    }

    func testFakeTokenStoreInitializesWithToken() throws {
        let store = FakeTokenStore(storedToken: "abc123")
        XCTAssertEqual(try store.loadToken(), "abc123")
    }

    func testFakeTokenStoreSaveAndLoad() throws {
        let store = FakeTokenStore()
        try store.saveToken("my-secret-token")
        XCTAssertEqual(try store.loadToken(), "my-secret-token")
    }

    func testFakeTokenStoreSaveOverwrites() throws {
        let store = FakeTokenStore(storedToken: "old-token")
        try store.saveToken("new-token")
        XCTAssertEqual(try store.loadToken(), "new-token")
    }

    func testFakeTokenStoreDelete() throws {
        let store = FakeTokenStore(storedToken: "to-delete")
        try store.deleteToken()
        XCTAssertNil(try store.loadToken())
    }

    func testFakeTokenStoreDeleteNonexistentIsIdempotent() throws {
        let store = FakeTokenStore()
        // Should not throw.
        try store.deleteToken()
        XCTAssertNil(try store.loadToken())
    }

    func testFakeTokenStoreDeleteThenSave() throws {
        let store = FakeTokenStore(storedToken: "initial")
        try store.deleteToken()
        XCTAssertNil(try store.loadToken())
        try store.saveToken("after-delete")
        XCTAssertEqual(try store.loadToken(), "after-delete")
    }

    // MARK: - Protocol conformance

    func testTokenStoreProtocolRoundTrip() throws {
        let store: TokenStore = FakeTokenStore()
        try store.saveToken("round-trip-token")
        XCTAssertEqual(try store.loadToken(), "round-trip-token")
        try store.deleteToken()
        XCTAssertNil(try store.loadToken())
    }

    // MARK: - Thread safety (basic smoke test)

    func testFakeTokenStoreConcurrentAccess() throws {
        let store = FakeTokenStore()
        let iterations = 100
        let group = DispatchGroup()

        for i in 0..<iterations {
            group.enter()
            DispatchQueue.global().async {
                try? store.saveToken("token-\(i)")
                _ = try? store.loadToken()
                group.leave()
            }
        }

        group.wait()
        // Should not crash. Final value is one of the tokens.
        XCTAssertNotNil(try store.loadToken())
    }
}

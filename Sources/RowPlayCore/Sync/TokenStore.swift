import Foundation

/// Protocol for Concept2 BYOT (bring-your-own-token) credential storage.
///
/// Implementations must never write tokens to UserDefaults, plain files,
/// logs, fixtures, or test assertions. The only acceptable storage backends
/// are the system Keychain (production) and in-memory (tests/previews).
public protocol TokenStore: Sendable {
    /// Persist a Concept2 access token, replacing any existing value.
    func saveToken(_ token: String) throws
    /// Load the stored token, or nil if none exists.
    func loadToken() throws -> String?
    /// Delete the stored token (disconnect/logout).
    func deleteToken() throws
}

/// Errors specific to token store operations.
public enum TokenStoreError: Error, Equatable {
    /// The token string could not be encoded as UTF-8 data.
    case encodingFailed
    /// A Keychain framework error occurred. The OSStatus value is preserved for diagnostics.
    case keychainError(OSStatus)
}

/// In-memory token store for tests and previews.
///
/// Holds the token as a plain `String?` property. This is the only
/// implementation where tokens are visible in memory — acceptable for
/// test control flow, never used in production.
public final class FakeTokenStore: TokenStore, @unchecked Sendable {
    private var storedToken: String?
    private let lock = NSLock()

    /// If set, `saveToken` throws this error instead of storing the token.
    public var saveError: Error?
    /// If set, `loadToken` throws this error instead of returning the stored token.
    public var loadError: Error?
    /// If set, `deleteToken` throws this error instead of clearing the stored token.
    public var deleteError: Error?

    public init(storedToken: String? = nil) {
        self.storedToken = storedToken
    }

    public func saveToken(_ token: String) throws {
        if let saveError { throw saveError }
        lock.withLock {
            storedToken = token
        }
    }

    public func loadToken() throws -> String? {
        if let loadError { throw loadError }
        return lock.withLock {
            storedToken
        }
    }

    public func deleteToken() throws {
        if let deleteError { throw deleteError }
        lock.withLock {
            storedToken = nil
        }
    }
}

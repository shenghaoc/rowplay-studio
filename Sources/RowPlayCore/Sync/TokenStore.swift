import Foundation
import Synchronization

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
public enum TokenStoreError: Error, Equatable, Sendable {
    /// The token string could not be encoded as UTF-8 data.
    case encodingFailed
    /// A Keychain framework error occurred. The OSStatus raw value is preserved for diagnostics.
    case keychainError(Int32)
}

/// In-memory token store for tests and previews.
///
/// Holds the token as a plain `String?` property. This is the only
/// implementation where tokens are visible in memory — acceptable for
/// test control flow, never used in production.
public final class FakeTokenStore: TokenStore {
    private struct State: Sendable {
        var storedToken: String?
        var saveError: (any Error)?
        var loadError: (any Error)?
        var deleteError: (any Error)?
    }

    private let state: Mutex<State>

    /// If set, `saveToken` throws this error instead of storing the token.
    public var saveError: (any Error)? {
        get { state.withLock { $0.saveError } }
        set { state.withLock { $0.saveError = newValue } }
    }
    /// If set, `loadToken` throws this error instead of returning the stored token.
    public var loadError: (any Error)? {
        get { state.withLock { $0.loadError } }
        set { state.withLock { $0.loadError = newValue } }
    }
    /// If set, `deleteToken` throws this error instead of clearing the stored token.
    public var deleteError: (any Error)? {
        get { state.withLock { $0.deleteError } }
        set { state.withLock { $0.deleteError = newValue } }
    }

    public init(storedToken: String? = nil) {
        self.state = Mutex(State(storedToken: storedToken))
    }

    public func saveToken(_ token: String) throws {
        try state.withLock {
            if let error = $0.saveError { throw error }
            $0.storedToken = token
        }
    }

    public func loadToken() throws -> String? {
        try state.withLock {
            if let error = $0.loadError { throw error }
            return $0.storedToken
        }
    }

    public func deleteToken() throws {
        try state.withLock {
            if let error = $0.deleteError { throw error }
            $0.storedToken = nil
        }
    }
}

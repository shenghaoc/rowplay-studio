import Foundation
#if canImport(Security)
import Security
#endif

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

#if canImport(Security)
/// Keychain-backed token store for production use.
///
/// Uses Security framework directly with `kSecClassGenericPassword` and
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` accessibility.
public final class KeychainTokenStore: TokenStore {
    private let service: String
    private let account: String

    /// - Parameters:
    ///   - service: Keychain service name. Defaults to the app's bundle identifier scoped token.
    ///   - account: Keychain account name. Defaults to `"default"`.
    public init(
        service: String = "com.rowplay-studio.concept2-token",
        account: String = "default"
    ) {
        self.service = service
        self.account = account
    }

    public func saveToken(_ token: String) throws {
        guard let data = token.data(using: .utf8) else {
            throw TokenStoreError.encodingFailed
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Try updating an existing item first; fall through to add only if not found.
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            break // fall through to add
        default:
            throw TokenStoreError.keychainError(updateStatus)
        }

        // No existing item — add a new one.
        let addQuery = query.merging([
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]) { _, new in new }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let retryStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
            guard retryStatus == errSecSuccess else {
                throw TokenStoreError.keychainError(retryStatus)
            }
        default:
            throw TokenStoreError.keychainError(addStatus)
        }
    }

    public func loadToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let token = String(data: data, encoding: .utf8) else {
                return nil
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw TokenStoreError.keychainError(status)
        }
    }

    public func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound is not an error — deleting a non-existent token is idempotent.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw TokenStoreError.keychainError(status)
        }
    }
}
#endif

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

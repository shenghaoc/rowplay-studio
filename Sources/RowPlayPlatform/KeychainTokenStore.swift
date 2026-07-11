import Foundation
import RowPlayCore
import Security

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

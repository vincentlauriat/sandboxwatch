import Foundation
import Security

/// Where a sandbox's `SANDBOX_TOKEN` lives. A protocol so that no test ever touches the
/// real Keychain — running the suite must never prompt for a login password.
public protocol TokenStore {
    func token(for sandbox: String) throws -> String?
    func setToken(_ token: String, for sandbox: String) throws
    func removeToken(for sandbox: String) throws
}

/// Test double.
public final class InMemoryTokenStore: TokenStore {
    private var tokens: [String: String]

    public init(_ seed: [String: String] = [:]) { self.tokens = seed }

    public func token(for sandbox: String) throws -> String? { tokens[sandbox] }
    public func setToken(_ token: String, for sandbox: String) throws { tokens[sandbox] = token }
    public func removeToken(for sandbox: String) throws { tokens[sandbox] = nil }
}

/// The real store: one generic password per sandbox, under a single service name.
public final class KeychainTokenStore: TokenStore {
    public static let defaultService = "fr.lauriat.sandboxwatch"
    private let service: String

    public init(service: String = KeychainTokenStore.defaultService) {
        self.service = service
    }

    private func baseQuery(_ sandbox: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: sandbox,
        ]
    }

    public func token(for sandbox: String) throws -> String? {
        var query = baseQuery(sandbox)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let token = String(data: data, encoding: .utf8) else {
                throw SandboxWatchError("keychain item for '\(sandbox)' is not readable text")
            }
            return token
        case errSecItemNotFound:
            return nil
        default:
            throw SandboxWatchError("keychain read failed for '\(sandbox)' (OSStatus \(status))")
        }
    }

    /// Replaces rather than duplicates: the Keychain would otherwise accept a second item
    /// with the same service and account, and reads would return an arbitrary one of them.
    public func setToken(_ token: String, for sandbox: String) throws {
        try removeToken(for: sandbox)
        var query = baseQuery(sandbox)
        query[kSecValueData as String] = Data(token.utf8)
        query[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SandboxWatchError("keychain write failed for '\(sandbox)' (OSStatus \(status))")
        }
    }

    public func removeToken(for sandbox: String) throws {
        let status = SecItemDelete(baseQuery(sandbox) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SandboxWatchError("keychain delete failed for '\(sandbox)' (OSStatus \(status))")
        }
    }
}

/// Reads a token, or explains exactly how to set one.
public func requireToken(_ store: TokenStore, for sandbox: String) throws -> String {
    guard let token = try store.token(for: sandbox), !token.isEmpty else {
        throw SandboxWatchError(
            "no token in the keychain for '\(sandbox)' — set one with: sbw sandbox add \(sandbox) --url <url>")
    }
    return token
}

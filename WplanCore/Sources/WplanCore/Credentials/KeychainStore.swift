import Foundation
import Security

public struct KeychainStore {
    public enum StoreError: Error {
        case unexpectedStatus(OSStatus)
        case corruptedData
    }

    private let service: String
    private let account = "wplan-credentials"

    public init(service: String) {
        self.service = service
    }

    public func save(_ credentials: WplanCredentials) throws {
        let payload = try JSONEncoder().encode(CodablePair(username: credentials.username, password: credentials.password))
        try? delete()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: payload
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
    }

    public func load() throws -> WplanCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw StoreError.unexpectedStatus(status) }
        guard let data = result as? Data else { throw StoreError.corruptedData }
        let pair = try JSONDecoder().decode(CodablePair.self, from: data)
        return WplanCredentials(username: pair.username, password: pair.password)
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unexpectedStatus(status)
        }
    }
}

private struct CodablePair: Codable {
    let username: String
    let password: String
}

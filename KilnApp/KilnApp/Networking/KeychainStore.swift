import Foundation
import Security

/// Tiny Keychain wrapper for storing the server host/port and a user passphrase.
enum KeychainStore {
    private static let service = "com.binkkiln.KilnApp"

    static func setString(_ value: String, for account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func getString(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func remove(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Persisted server connection info.
struct ServerConnection: Equatable, Sendable {
    var host: String
    var port: Int

    static let hostAccount = "server.host"
    static let portAccount = "server.port"

    static var saved: ServerConnection? {
        guard let host = KeychainStore.getString(for: hostAccount),
              let portStr = KeychainStore.getString(for: portAccount),
              let port = Int(portStr), !host.isEmpty else { return nil }
        return ServerConnection(host: host, port: port)
    }

    func save() {
        KeychainStore.setString(host, for: Self.hostAccount)
        KeychainStore.setString(String(port), for: Self.portAccount)
    }

    static func clear() {
        KeychainStore.remove(account: hostAccount)
        KeychainStore.remove(account: portAccount)
    }

    var httpBase: URL { URL(string: "http://\(host):\(port)")! }
    var wsBase: URL { URL(string: "ws://\(host):\(port)")! }
}

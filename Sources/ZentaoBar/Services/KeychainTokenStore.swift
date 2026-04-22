import Foundation
import Security

struct KeychainTokenStore {
    private let service = "com.codex.zentaobar.token"

    func loadToken(baseURL: String, account: String) -> String? {
        let key = tokenKey(baseURL: baseURL, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }

        return token
    }

    func saveToken(_ token: String, baseURL: String, account: String) throws {
        let key = tokenKey(baseURL: baseURL, account: account)
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess {
            return
        }

        guard status == errSecItemNotFound else {
            throw ZentaoAPIError.message("保存 token 失败。")
        }

        var newItem = query
        newItem[kSecValueData as String] = data
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw ZentaoAPIError.message("保存 token 失败。")
        }
    }

    func deleteToken(baseURL: String, account: String) {
        let key = tokenKey(baseURL: baseURL, account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        SecItemDelete(query as CFDictionary)
    }

    private func tokenKey(baseURL: String, account: String) -> String {
        "\(baseURL)|\(account)"
    }
}

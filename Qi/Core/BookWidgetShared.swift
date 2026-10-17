import Foundation
import Security

// ⚠️ 这个文件在 `Qi/Core/` 和 `QiIsland/` 里**各有一份，内容一样**，改一份就要同步改另一份。
//
// 桌面小组件读记账汇总用的。她用的签名证书不带 App Group，App 和小组件之间没有共用的文件夹；
// 但证书允许共用钥匙串（keychain-access-groups 是「团队号.*」），所以汇总写在钥匙串里。

/// 写给小组件看的一份记账汇总
struct BookWidgetSnapshot: Codable {
    struct Cat: Codable, Hashable {
        var name: String
        var symbol: String
        var amount: Double
    }
    var updated = Date()
    /// 哪个月（yyyy-MM）
    var month = ""
    var monthTitle = ""
    var total = 0.0
    var categories: [Cat] = []
    /// 这个月每天花了多少（下标 0 = 1 号）
    var days: [Double] = []
    /// 1 号是星期几（1 = 周日）
    var firstWeekday = 1
    var levels: [Double] = [50, 100, 200, 500]
    var accentHex = "C47A5A"
}

enum SharedKeychain {

    private static let service = "qi.shared"

    /// 「团队号」前缀：存一条不指定组的，读回它落在哪个组
    private static func prefix() -> String? {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "qi.probe",
            kSecAttrAccount as String: "probe"
        ]
        var q = base
        q[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        var status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = Data("1".utf8)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            add[kSecReturnAttributes as String] = true
            status = SecItemAdd(add as CFDictionary, &result)
        }
        guard status == errSecSuccess,
              let attrs = result as? [String: Any],
              let group = attrs[kSecAttrAccessGroup as String] as? String,
              let dot = group.firstIndex(of: ".") else { return nil }
        return String(group[..<dot])
    }

    private static var group: String? { prefix().map { $0 + ".qi.shared" } }

    @discardableResult
    static func write(_ data: Data, key: String) -> Bool {
        guard let group else { return false }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: group
        ]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func read(key: String) -> Data? {
        guard let group else { return nil }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: group,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}

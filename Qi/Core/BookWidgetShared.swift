import Foundation
import Security
import UIKit

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

    /// 上一次读写的结果（0 = 成功），出问题时显示出来好查
    nonisolated(unsafe) static var lastStatus: OSStatus = 0
    /// 上一次用的钥匙串组
    nonisolated(unsafe) static var lastGroup = ""
    /// 钥匙串不通的时候走的那条备用路：同一个开发者的私有剪贴板（不是系统那个大剪贴板，别的 App 看不见）
    nonisolated(unsafe) static var lastBoard = ""
    /// 一句话写清楚上一次卡在哪
    static var diagnosis: String {
        let key = lastStatus == 0 ? "钥匙串正常" : "钥匙串代码 \(lastStatus)"
        return lastBoard.isEmpty ? key + " · 组 \(lastGroup.isEmpty ? "没拿到" : lastGroup)" : key + " · " + lastBoard
    }

    private static let boardName = "qi.shared.book"
    private static let boardType = "qi.book.snapshot"

    private static func boardWrite(_ data: Data, key: String) {
        guard let b = UIPasteboard(name: UIPasteboard.Name(boardName + "." + key), create: true) else {
            lastBoard = "备用路建不起来"
            return
        }
        b.setData(data, forPasteboardType: boardType)
        lastBoard = "备用路已写"
    }

    private static func boardRead(key: String) -> Data? {
        guard let b = UIPasteboard(name: UIPasteboard.Name(boardName + "." + key), create: false) else {
            lastBoard = "备用路没找到"
            return nil
        }
        let d = b.data(forPasteboardType: boardType)
        lastBoard = d == nil ? "备用路是空的" : "走的备用路"
        return d
    }

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
        if status != errSecSuccess { lastStatus = status }
        guard status == errSecSuccess,
              let attrs = result as? [String: Any],
              let group = attrs[kSecAttrAccessGroup as String] as? String,
              let dot = group.firstIndex(of: ".") else { return nil }
        return String(group[..<dot])
    }

    private static var group: String? { prefix().map { $0 + ".qi.shared" } }

    @discardableResult
    static func write(_ data: Data, key: String) -> Bool {
        lastStatus = 0
        // 两条路都写：钥匙串不通（签名不带共享权限，代码 -34018）的时候小组件读备用那条
        boardWrite(data, key: key)
        guard let group else { lastGroup = ""; if lastStatus == 0 { lastStatus = -1 }; return lastBoard == "备用路已写" }
        lastGroup = group
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
        lastStatus = SecItemAdd(add as CFDictionary, nil)
        return lastStatus == errSecSuccess || lastBoard == "备用路已写"
    }

    static func read(key: String) -> Data? {
        lastStatus = 0
        lastBoard = ""
        guard let group else { lastGroup = ""; if lastStatus == 0 { lastStatus = -1 }; return boardRead(key: key) }
        lastGroup = group
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: group,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        lastStatus = SecItemCopyMatching(q as CFDictionary, &result)
        guard lastStatus == errSecSuccess else { return boardRead(key: key) }
        return result as? Data
    }
}

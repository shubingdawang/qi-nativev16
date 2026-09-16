import Foundation
import Security

/// 扩展和主 App 之间那个小格子（钥匙串里的两个条目）。
///
/// ⚠️⚠️ **广播扩展里有一份一模一样的**（`QiBroadcast/ScreenShare.swift`）。
/// 两个 target 各自是一个同步文件夹，没法共用一个文件——
/// 改这边的条目名、分组名，那边必须一起改，不然两头各说各的。
enum ScreenShare {

    static let frameAccount = "qi.screen.frame"
    static let stateAccount = "qi.screen.state"
    private static let service = "qi.screen"

    /// `TEAMID.qi.screen`。
    ///
    /// 证书换了 TEAMID 就跟着变，所以**不写死**：先往默认分组里放一个探针条目，
    /// 读回来看它落在哪个分组（形如 `TEAMID.com.xxx`），取点号前面那段。
    static var group: String? = {
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "qi.probe",
            kSecAttrAccount as String: "qi.probe",
        ]
        var add = probe
        add[kSecValueData as String] = Data([1])
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)

        var q = probe
        q[kSecReturnAttributes as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let attrs = out as? [String: Any],
              let g = attrs[kSecAttrAccessGroup as String] as? String,
              let team = g.split(separator: ".").first
        else { return nil }
        return team + ".qi.screen"
    }()

    private static func base(_ account: String) -> [String: Any]? {
        guard let group else { return nil }
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
        ]
    }

    private static func put(_ data: Data, _ account: String) {
        guard let q = base(account) else { return }
        let update: [String: Any] = [kSecValueData as String: data]
        if SecItemUpdate(q as CFDictionary, update as CFDictionary) == errSecItemNotFound {
            var add = q
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    private static func get(_ account: String) -> Data? {
        guard var q = base(account) else { return nil }
        q[kSecReturnData as String] = true
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess else { return nil }
        return out as? Data
    }

    /// 最新一帧：前 8 个字节是截下来的时间（秒，小端），后面是 JPEG
    static func writeFrame(_ jpeg: Data, at: Date) {
        var t = at.timeIntervalSince1970.bitPattern.littleEndian
        var d = Data(bytes: &t, count: 8)
        d.append(jpeg)
        put(d, frameAccount)
    }

    static func readFrame() -> (jpeg: Data, at: Date)? {
        guard let d = get(frameAccount), d.count > 8 else { return nil }
        let bits = d.prefix(8).withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }
        let at = Date(timeIntervalSince1970: Double(bitPattern: UInt64(littleEndian: bits)))
        return (d.dropFirst(8), at)
    }

    /// 正在广播没有（「1|时间」/「0|时间」）
    static func writeState(live: Bool) {
        put("\(live ? 1 : 0)|\(Date().timeIntervalSince1970)".data(using: .utf8)!, stateAccount)
    }

    static func readLive() -> Bool {
        guard let d = get(stateAccount), let s = String(data: d, encoding: .utf8) else { return false }
        return s.hasPrefix("1")
    }
}
